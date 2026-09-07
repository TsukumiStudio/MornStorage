# MornStorage

ディスク使用量をツリーマップで可視化する Mac アプリです (SpaceSniffer 風)。
macOS 14 以降対応。

## Homebrew での導入

```bash
brew install --cask tsukumistudio/tap/mornstorage
```

## Homebrew での更新

```bash
brew update
brew upgrade --cask mornstorage
```

アプリ内の「更新を確認」からも更新できます。

## Homebrew でのアンインストール

```bash
brew uninstall --cask mornstorage
```

## 使い方

1. 「ボリュームを選択」でスキャンするディスクを選びます。スキャン中も見つかった順に描画されます。
2. 面積がサイズに比例したタイルで表示されます。枠線だけのものがフォルダ、色付きタイルがファイルで、色は拡張子ごとに決まります。
3. 右上の ⊟ ⊞ で表示する階層の深さを増減できます (設定は保持されます)。
4. 矩形にカーソルを合わせると下部にパスとサイズが出ます。フォルダをクリックすると中身を開閉できます (開いているものは畳まれ、畳まれたものは 1 階層開きます)。
5. 右クリック →「Finderで表示」で該当項目を Finder で開きます。
6. ウィンドウを閉じるとアプリごと終了します。

環境変数 `MORNSTORAGE_PATH` にパスを入れて起動すると、そのパスを即座にスキャンします。

```bash
open -a MornStorage --env MORNSTORAGE_PATH="$HOME"
```

## 開発

```bash
swift test
zsh build.sh   # dist/MornStorage.app
```

## ライセンス

[The Unlicense](LICENSE)
