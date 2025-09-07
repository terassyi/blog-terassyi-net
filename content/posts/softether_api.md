+++
categories = [ "tech" ]
tags = [ "softether", "golang", "network", "oss" ]
date = 2020-07-15
title = "SoftEther VPN Server APIのGo版を作った"
description = "softetherを使用しているのでAPIのGo版を作った"
+++

こんにちは．最近は学校の課題や事務手続きやらインターンどうしようかやらで非常に忙しいです．それに加えてSecHack365に参加することとなりこれはうれしい悲鳴ですがさらに忙しいです．(嬉しい)
さて今回はSoftEtherについてです．学生などにはあまり馴染みがなさげなソフトですが，僕は研究でこのソフトに非常にお世話になっております．このソフトウェアはとてもすごいんですが，マネージャーソフトがwindows用しかなくてCUIベースの操作が大変なのでWebベースのマネージャーを作ろうと思い立ちました．そこでまずGo言語でAPIのラッパーを作成しました．

<!--more-->

## SoftEther VPN
SoftEther VPNは登大遊さんによって開発され，現在筑波大学の研究プロジェクトとしてApache License 2.0で運営されているソフトウェアVPNです．有償版としてソフトイーサ株式会社よりPacketiX VPN 4.0が提供されています．詳しくは[公式サイト](https://ja.softether.org/)をご覧ください.

## API
SoftEther VPN Serverには2019年7月7日にリリースされたバージョンから組込のWebマネージャーとJSON-RPC APIが実装されています．しかし，Webマネージャーよりも柔軟にサーバーを管理したかったのでAPIを使用することにしました．しかし，僕の使用したいGo言語は公式のサポートがないので今回は自作することにしました．
MITライセンスで公開しているので是非使ってみてください．
リポジトリはこちら．[terassyi/go-softether-api](https://github.com/terassyi/go-softether-api)

{{<github repo="terassyi/go-softether-api">}}

## 使い方
基本的使用法は[公式ドキュメント](https://github.com/SoftEtherVPN/SoftEtherVPN/tree/master/developer_tools/vpnserver-jsonrpc-clients/)を参照してください．
以下がテストメソッドをコールするサンプルコードです．
```go
package main

import (
	"fmt"
	softether "github.com/terassyi/go-softether-api"
	"github.com/terassyi/go-softether-api/methods"
)

func main() {
	api := softether.New("localhost", 443, "default", "password")
	method := methods.NewTest()
	res, err := api.Call(method)
	if err != nil {
		panic(err)
	}
	fmt.Println(res)
}
```
まずは以下のようにインポートしてください．
```go
softether "github.com/terassyi/go-softether-api"
```
次に接続するサーバーのアドレスとVPNハブの名前，パスワードを入力してVPNサーバーに接続します．
```go
api := softether.New("localhost", 443, "default", "password")
```
サンプルなのでlocalに接続しています．この時，実際に接続されるurlは`https://localhost/api/`となります．この時，証明書を無視してhttpsのリクエストを送るように設定しています．ですので，インターネット経由でリクエストを送信するのは避けましょう．
その後，コールしたいメソッドのインスタンスを作成して`api.Call()`でAPIをコールします．
定義されているメソッドは`/methods`にあります．現在全てのメソッドはサポートしていません．僕の必要に応じて実装します．また，各メソッドの実体は`pkg.Method`インターフェースを実装しているのでいい感じに`Call()`で呼び出せます．
レスポンスに関しては`map[string]interface{}`で取り出してるので時間があればこちらも整備します．

## まとめ
SoftEther VPNは非常に便利なソフトです．OSSなので遊んでみるのもいかがでしょうか．
