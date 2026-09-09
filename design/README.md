# MornStorage 画像素材

- `ogp.psd` / `ogp.png`: 1200 × 630。
- `icon.psd` / `icon.png`: 1024 × 1024、クリーム色の不透明背景。
- `ogp.psd`の背景 (グリッド・グラデーション) はMornDesktopTubeの`design/ogp.psd`から背景レイヤー群を複製し1200×630へ縮小したもの。文字・バッジ・ウィンドウは「MornStorage 前景（ラスター）」1枚のラスターレイヤーで、個別編集用レイヤーは含みません。
- `icon.psd`は画像を収めたラスターレイヤー形式。
- MornDesktopTubeのOGPを配色とレイアウトの参考に、組み込み画像生成ツールで制作。
- OGPはルートREADMEに表示。`icon.png`から作成した`Support/AppIcon.icns`を、`build.sh`でアプリに同梱します（16・32・128・256・512pxと各2倍解像度）。アイコン変更時はICNSも更新してください。

## 生成プロンプト

アイコンは生成後、外周ノイズを避けるため影を除去し、背景を不透明なクリーム色へ変更。
最終修正: "Replace the entire checkerboard background with a solid uniform pale cream color matching the base. Fully opaque square image, no transparency, no checkerboard, no external shadow. Preserve the four treemap blocks, their arrangement and olive/lime/sage colors. No text."

### OGP

Use case: ads-marketing. Create a finished MornStorage OGP banner, landscape 1200x630. Reference image is style/composition reference only, not the same product. Match its crisp flat graphic aesthetic, very pale cream grid background, olive typography and soft lime accents, restrained soft shadows, generous spacing. On left brand MornStorage with a tiny treemap mark. Large exact Japanese headline split over two lines: "ディスクの中身を、" and "ひと目で。" Supporting exact text: "容量をツリーマップで見える化。" Bottom left pill badges "Homebrew 対応" and "macOS 14+"; small footer "TSUKUMI STUDIO". Right side a large simplified Mac app window containing an elegant treemap of rectangles of varied sizes with consistent cream gutters, olive/lime/sage main tiles and sparse blue accent tiles; no invented text within diagram. Diagram should clearly communicate disk usage by area, no pie chart, no play buttons, no YouTube icon, no mountains. Polished readable Japanese typesetting. Keep all content safely inset.

### アイコン

Use case: logo-brand. Create a finished MornStorage macOS app icon, square 1024x1024. Reference is palette/style only. A single large centered rounded-square cream app tile, with a crisp treemap symbol inside: one large olive rectangle on left, smaller lime, sage, olive rectangles stacked on right and bottom with consistent cream gutters. Flat clean geometric graphic, restrained soft shadow only around outer tile, same olive and yellow-green family as reference. Treemap symbol recognizable at 32px, generous inset margin, no text, no letters, no numbers, no play button, no YouTube motif, no mountains, no grid behind icon. Transparent canvas outside the rounded-square tile. Professional macOS utility icon.
