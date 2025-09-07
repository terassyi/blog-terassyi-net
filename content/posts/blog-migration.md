+++
categories = [ "activity" ]
tags = [ "blog", "vuepress" ]
date = 2020-03-29
title = "もろもろを移行する"
description = "migration of my blog"
+++

## もろもろを移行する

僕個人が運用しているもろもろを移行します．

### 移行するもの

- ホームページ(これはほんとにひどい)
- ブログ
- twitterのID(名前変えただけ)
- GithubのID(名前変えただけ)

### 動機

アウトプットの場としてブログを運用し始めたのですが，いざ記事を書こうとすると億劫になってなかなか手がすすみません．
原因は何かと考えた時にブログポストのために毎回WordpressのページにログインしたりMarkdownでかけないあたりだと思い立ちました．
そこでブログをMarkdownで書ける静的サイトジェネレータに移行しようと思いました．
ついでに最近しっくりきていなかった*spectrex02*というハンドルネームも移行しようと考えてもろもろを移行してしまいます．
(*spextrex02*というハンドルネームは元々僕が自費で初めて購入したHPのPCの製品名が由来)

### ホームページ

これはひどいのでなくしちゃいます．

### ブログ

これまではWordpressをEC2上で動かしてました．
カスタムドメインを使用するのでRoute53にドメイン登録してたんですが結構費用がかかるんですよね．
かつWordpressだと記事書くのが結構めんどくさいのでMarkdownで書けるVuepressに移行します．
ReactのGatsbyにしようかと考えましたがReact分からなくてしっくりこなかったのでVueを使用したVuepressにしました．
テーマは[vuepress-theme-meteorlxy](https://vuepress-theme-meteorlxy.meteorlxy.cn/posts/2019/02/27/theme-guide-en.html)を使用しています．
ほとんど変わったことはしていないので導入は公式に従って進めました．
公開はGithub Pagesで行います．カスタムドメインやHTTPSにも対応してるしリポジトリのsettingページから簡単にできました．すごい．

### その他アカウント

TwitterやGithubのアカウント名も合わせて*spectrex02*から*terassyi*に変更しました．

### まとめ

ブログをvuepressに移行して爆速でポストできるようになった(はず)なのでこれから頑張りたいです．
vuepressもGithub Pagesも簡単でめっちゃいいです．
