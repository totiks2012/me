// torsearch.go — поиск раздач по qBitTorrent-подобным источникам для me tomv -s.
// Порт логики плагина rutor (imDMG) + apibay (TPB JSON) + nyaa.si RSS.
// Вывод одной строкой на результат, столбцы через TAB:
//   magnet  seeds  size  title
// (отсортировано по сидам по убыванию, дедуп по infohash)
package main

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	ua  = "Mozilla/5.0 (X11; Linux i686; rv:38.0) Gecko/20100101 Firefox/38.0"
	nyaaNs = "https://nyaa.si/xmlns/nyaa"
	dirURL = "https://rutor.info/"
)

var client = &http.Client{Timeout: 12 * time.Second}

type item struct {
	magnet string
	seeds  int
	size   string
	title  string
	key    string // infohash (hex, lowercase) для дедупа
}

func getBytes(u string) ([]byte, error) {
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", ua)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
}

// ---------------- rutor (HTML, порт плагина) ----------------

var reRutor = regexp.MustCompile(`(?s)(?:gai|tum)"><td>(.+?)</td.+?href="(magnet:.+?)".+?href="/(?:torrent/\d+).+?">(.+?)</a.+?right">([.\d]+?&nbsp;\w+?)</td.+?<span.+?(\d+?)</span>.+?<span.+?(\d+?)</span>`)
var reTag = regexp.MustCompile(`<[^>]*>`)

func searchRutor(q string) ([]item, error) {
	u := dirURL + "search/0/0/000/0/" + url.QueryEscape(q)
	body, err := getBytes(u)
	if err != nil {
		return nil, err
	}
	var out []item
	for _, m := range reRutor.FindAllSubmatch(body, -1) {
		name := html.UnescapeString(string(reTag.ReplaceAll(m[3], nil)))
		size := html.UnescapeString(string(m[4]))
		it := item{
			magnet: string(m[2]),
			seeds:  atoi(m[5]),
			size:   strings.ReplaceAll(size, "&nbsp;", " "),
			title:  html.UnescapeString(name),
		}
		it.key = btihHex(it.magnet)
		if it.key != "" && it.title != "" {
			out = append(out, it)
		}
	}
	return out, nil
}

// ---------------- apibay (TPB JSON) ----------------

type bayRes struct {
	Name     string `json:"name"`
	InfoHash string `json:"info_hash"`
	Seeders  string `json:"seeders"`
	Size     string `json:"size"`
}

func searchApibay(q string) ([]item, error) {
	u := "https://apibay.org/q.php?q=" + url.QueryEscape(q)
	body, err := getBytes(u)
	if err != nil {
		return nil, err
	}
	var rs []bayRes
	if err := json.Unmarshal(body, &rs); err != nil {
		return nil, err
	}
	var out []item
	for _, r := range rs {
		hash := strings.ToLower(strings.TrimSpace(r.InfoHash))
		if hash == "" {
			continue
		}
		it := item{
			magnet: "magnet:?xt=urn:btih:" + hash + "&dn=" + url.QueryEscape(r.Name),
			seeds:  atoi([]byte(r.Seeders)),
			size:   humanSize(atoi([]byte(r.Size))),
			title:  html.UnescapeString(r.Name),
			key:    hash,
		}
		out = append(out, it)
	}
	return out, nil
}

// ---------------- nyaa (RSS) ----------------

type nyaaItem struct {
	Title    string `xml:"title"`
	InfoHash string `xml:"https://nyaa.si/xmlns/nyaa infoHash"`
	Seeders  string `xml:"https://nyaa.si/xmlns/nyaa seeders"`
	Size     string `xml:"https://nyaa.si/xmlns/nyaa size"`
}

type nyaaRSS struct {
	Channel struct {
		Items []nyaaItem `xml:"item"`
	} `xml:"channel"`
}

func searchNyaa(q string) ([]item, error) {
	u := "https://nyaa.si/?page=rss&q=" + url.QueryEscape(q)
	body, err := getBytes(u)
	if err != nil {
		return nil, err
	}
	var rss nyaaRSS
	if err := xml.Unmarshal(body, &rss); err != nil {
		return nil, err
	}
	var out []item
	for _, r := range rss.Channel.Items {
		hash := strings.ToLower(strings.TrimSpace(r.InfoHash))
		if hash == "" {
			continue
		}
		it := item{
			magnet: "magnet:?xt=urn:btih:" + hash + "&dn=" + url.QueryEscape(r.Title),
			seeds:  atoi([]byte(r.Seeders)),
			size:   strings.TrimSpace(r.Size),
			title:  html.UnescapeString(r.Title),
			key:    hash,
		}
		out = append(out, it)
	}
	return out, nil
}

// ---------------- утилиты ----------------

func atoi(b []byte) int {
	n := 0
	for _, c := range b {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}

func humanSize(b int) string {
	f := float64(b)
	for _, u := range []string{"B", "KB", "MB", "GB", "TB"} {
		if f < 1024 || u == "TB" {
			return fmt.Sprintf("%.2f %s", f, u)
		}
		f /= 1024
	}
	return fmt.Sprintf("%d B", b)
}

// btihHex — выдрать btih-хеш (hex) из magnet-ссылки и привести к нижнему регистру.
func btihHex(mag string) string {
	i := strings.Index(mag, "btih:")
	if i < 0 {
		return ""
	}
	rest := mag[i+len("btih:"):]
	j := strings.IndexAny(rest, "&")
	if j >= 0 {
		rest = rest[:j]
	}
	return strings.ToLower(rest)
}

func main() {
	if len(os.Args) < 3 || os.Args[1] != "-q" {
		fmt.Fprintln(os.Stderr, "usage: torsearch -q \"запрос\" [-src rutor|apibay|nyaa|all]")
		os.Exit(2)
	}
	query := os.Args[2]
	src := "all"
	if len(os.Args) >= 5 && os.Args[3] == "-src" {
		src = os.Args[4]
	}

	type res struct {
		items []item
		err   error
	}
	run := func(fn func(string) ([]item, error)) []item {
		it, err := fn(query)
		if err != nil {
			fmt.Fprintln(os.Stderr, "torsearch: [warn]", err)
			return nil
		}
		return it
	}

	byKey := map[string]item{}
	dedup := func(it []item) {
		for _, x := range it {
			if x.key == "" {
				continue
			}
			prev, ok := byKey[x.key]
			if !ok || x.seeds > prev.seeds {
				byKey[x.key] = x
			}
		}
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	jobs := []struct {
		name string
		fn   func(string) ([]item, error)
	}{}
	if src == "all" || src == "rutor" {
		jobs = append(jobs, struct{ name string; fn func(string) ([]item, error) }{"rutor", searchRutor})
	}
	if src == "all" || src == "apibay" {
		jobs = append(jobs, struct{ name string; fn func(string) ([]item, error) }{"apibay", searchApibay})
	}
	if src == "all" || src == "nyaa" {
		jobs = append(jobs, struct{ name string; fn func(string) ([]item, error) }{"nyaa", searchNyaa})
	}

	for _, j := range jobs {
		wg.Add(1)
		go func(j struct{ name string; fn func(string) ([]item, error) }) {
			defer wg.Done()
			it := run(j.fn)
			mu.Lock()
			dedup(it)
			mu.Unlock()
		}(j)
	}
	wg.Wait()

	all := make([]item, 0, len(byKey))
	for _, x := range byKey {
		all = append(all, x)
	}
	sort.Slice(all, func(i, j int) bool {
		if all[i].seeds != all[j].seeds {
			return all[i].seeds > all[j].seeds
		}
		return all[i].title < all[j].title
	})

	for _, x := range all {
		fmt.Printf("%s\t%d\t%s\t%s\n", x.magnet, x.seeds, x.size, x.title)
	}
}