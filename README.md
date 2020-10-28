
# wallabag-captureweb

wallabagの記事のうち、サムネイルが取れなかったものに対してスクショを付与します。
pdfの場合は1ページ目です。

# 前提

* wallabagからもこのコンテナからもアクセスできるdavが必要
* davにはwallabagからはID/Passなしでアクセスできる状態
* wallabagの"Download images locally"を有効にすることにより、ユーザのブラウザからdavに到達できなくても問題はない

# 使い方

環境変数に以下のものを指定してください

* WALLABAG_URL wallabagのURL
* WALLABAG_CLIENT_ID
* WALLABAG_CLIENT_SECRET

* WALLABAG_USERNAME wallabagのユーザ名
* WALLABAG_PASSWORD wallabagのpassword

* DAV_URL このdavが使用するdavのURL

# 注意点

DAV_URLの下にほかのものがあってはだめです。

# 参照と謝辞

画像取得には以下を使用しています。
ありがとうございます。

[mokemokechicken/docker_capture_web: Docker Container to take full screenshot of a web page](https://github.com/mokemokechicken/docker_capture_web)

# License

私が書いた部分はGPLv3 or laterで。



