+++
categories = [ "activity" ]
tags = [ "blog", "cloudflare" ]
date = 2022-08-02
title = "ドメインをCloudflareに移管しました with Cloudflare tunnel"
description = "Cloudflare tunnelを使いたくてついでにドメインをCloudflareに移管しました"
+++

こんにちは．
今年度より学生生活を無事修了して社会に放たれました．
規則正しい生活をがんばっています．

## terassyi.netをCloudflareに移行した
私が管理するドメイン`terassyi.net`をお名前.comからCloudflareに移管しました．
特にリンク先が変わったり何かが変わったわけではありません．

<!--more-->

### 理由
個人的に[Cloudlfare tunnel](https://www.cloudflare.com/ja-jp/products/tunnel/)を利用して自宅のLANにremoteからSSH接続したく，この際なのでドメインごと移行しようということで移行しました．

### 変わったこと
特に変わったことはありませんがしいて言えば以下のことが変わりました．
- name server
- このブログのホスティング先
	`Github Pages`から`Cloudflare Pages`に移行しました．

### Cloudflare tunnel

<!-- https://x.com/terassyi_/status/1552687726364831744 -->
{{<x user="terassyi_" id="1552687726364831744">}}

グローバルIPは諸事情により取得していないのですが自宅のネットワークに外部から接続したい欲を抑えきれずプライベートアクセスソリューションを探していました．
最初はSoftEtherを利用しようかと考えていましたが同期に`Cloudflare tunnel`が便利と聞いたので思い立ったが吉日ということで導入しました．
非常に簡単に導入できて(しかも無料)感動しました．

導入フローは以下です．
1. Cloudflareにサインアップ
2. ドメインを登録
3. コントロールパネルからZero Trust > Access > Tunnel > Create a tunnelとすすむ
4. Tunnel nameを入力
5. 以下のようなコマンドが表示されるのでLAN側のマシンで実行

	```shell
	$ curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
		sudo dpkg -i cloudflared.deb &&  \
		sudo cloudflared service install <service_token>
	```
6. endpointとなるドメインと接続先のURLを入力

	例えば，`private.your.domain`, `ssh://<username>@localhost:22`
7. LANの外部にいる端末から`cloudflared access ssh --hostname private.your.domain`といった感じで接続する

	`ssh_config`に書いておくと便利．
	私は以下のようにconfigを登録しました．
	```
	Host private.terassyi.net
    	User altair
    	IdentityFile path/to/ssh_key
   		ProxyCommand /usr/local/bin/cloudflared access ssh --hostname %h
	```

これで快適なプライベートアクセス生活ができそうです．
これからもよろしくお願いします．
