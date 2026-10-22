# ドパリカ!

問題で世界をうごかす理科クイズ iOS アプリ (Swift / SwiftUI / SwiftData)。
元ネタ: [rikarikastudy](https://github.com/Ben-Kei-create/rikarikastudy)

## 構成
- `doparika/Models` — Question (JSON) / SwiftData モデル
- `doparika/Services` — QuizEngine, QuestionSelector(復習ミックス), LevelCalculator, WorldMotionController, CollectionService ほか
- `doparika/Views` — Home / Quiz / Result / Collection、画像優先・コード描画フォールバックの地層背景 (`WorldBackgroundView`)
- `doparika/Resources/questions_mountain.json` — 山ステージ問題 (ID は一度発行したら不変)
- `tools/build_questions.py` — rikarikastudy の choice4 問題を 2 択に変換 (既存ファイルがあると再生成を拒否)

## 対応端末・Bundle ID

- **iPhone専用・縦画面のみ**（`TARGETED_DEVICE_FAMILY = 1`、横画面・iPad は非対応）。
- Bundle ID は `com.fumiakimogi.doparika`。開発初期の `devplaceholder.*.doparika` から変更したため、旧ビルドの保存データ（XP・解放履歴）は引き継がれない。開発用データなので移行はしない（リリース前の仕様）。

## 初回リリース仕様（地球ステージ）
Lv.1〜30 / 地球ステージ / 2択 / 制限時間15秒 / 正解 +20XP

- **1回のプレイ**: Lv.1〜19は10問、Lv.20〜30は20問（Lv.20の境界は暫定で20問側）。
- **背景の動き**: 必ず `earth_001` の最上部（地表）から始まる。正解するたびに次の画像の最上部へ潜り、全問正解なら最後の画像（10問なら `earth_010`、20問なら `earth_020`）の最下部に着いてリザルトへ。考え中は地表側へ震えながらゆっくり戻り、不正解・時間切れでも地表側へ落ちる（位置はその問題の分だけ戻るだけで、次の問題で元の位置へ引き戻さない）。
- 毎回プレイ開始時は地表から。再挑戦時は前回の位置から地表へ上がってから始まる。

## 背景Assetの差し替え

- `home_bg`、`earth_001`〜`earth_020`（JPEG、667×2000相当・縦横比1:3）、`AppIcon` の名前を維持する。
- 地球ステージの素材は縦横比1:3。**1セクションの高さは画面幅の3倍**（`WorldMotionController.sectionAspect`）で、画像の上下端はクロップされず継ぎ目が保たれる。左右は中央基準のAspect Fillで、極端な縦横比の画像では左右がクロップされる。
- Asset内の画像だけを交換すればよく、Swiftコードやセクション位置の変更は不要。解像度やAssetのscale指定が変わってもセクションの高さは変わらない。
- 画面に交差するセクションだけを描画する。隣接セクションは高さの12%（`overlapFraction`）だけ重ね、重なり部分を smoothstep でクロスフェードして継ぎ目を見せない。重なり部分では二つの絵が溶け合うため、境界付近の化石などが薄く二重に見えることがある（素材側で境界付近を無地寄りにすると改善）。
- `home_bg` が欠けた場合は地層背景へ、各 `earth_XXX` が欠けた場合はその区間だけコード描画へ戻る。
- ロゴ、羊皮紙、正誤・満点演出、空・海ティザーの追加素材は未導入。

## 宇宙・深海ステージ（実装済み・リリース1では非表示）

- スイッチは `FeatureFlags.extraStagesShipped`（`doparika/Models/StageConfig.swift`）。**リリース2では `true` にするだけ**で、宇宙（Lv.31-60）・深海（Lv.61-100）、Lv上限100、ホームのステージ選択、コレクションのタブが有効になる。リリース1（`false`）ではレベル上限30・地球のみで、ステージ行もタブも表示されない。
- デバッグビルドでは起動引数 `-debugStages YES`（と `-debugXP 15000` でLv.35）で確認できる。
- ステージ差分は `Stage.config`（画像の接頭辞・枚数・向き・Lv範囲・BGM）に集約。宇宙は **上昇**（`space_001` の下端＝地表から始まり、正解で上へ。ワールドを上下反転して描画、画像自体は正立）、深海は地球と同じ **潜行**（`sea_001`〜`sea_030`）。
- 問題は `questions_mountain.json` / `questions_sky.json` / `questions_sea.json`。IDは全ステージで通し番号（一意）。追加は `tools/import_questions_txt.py FILE.txt --stage sky|sea`（`tools/question_sources/` に現在の元データ）。
- 現在の問題数: 地球955 / 宇宙35 / 深海38。**宇宙・深海は初期の少数で、リリース2までに増やして内容を確認する必要がある**（Lv31-100の長さに対して不足）。
- 1回の問題数: 地球 Lv.1-20=10 / 21+=20、宇宙=20、深海=20（Lv.81+は30）。過去ステージの復習プレイは獲得XP×0.5。
- 深海専用BGMは未制作（暫定でホームBGM）。

## 問題データ

- `tools/build_questions.py` — 初回生成（既存ファイルがあると拒否）。
- `tools/fetch_supabase.py` — rikarikastudy の Supabase から2択化できる問題を **追記のみ** で取り込む（既存IDは不変、`--dry-run` あり）。`.env` に `SUPABASE_URL` / `SUPABASE_KEY`（Publishable key）を置く。`.env` はコミットしない。
- 地球ステージは 955 問（`00001`〜`00955`）。

## 検証

### 自動テスト（XCTest）

```sh
xcodebuild -project doparika.xcodeproj -scheme doparika -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

`doparikaTests`: 背景モーション（境界・回転・ドリフト上限）、回答期限・一時停止・問題切替の時計、再挑戦の位置継承、保存（XP・解放・誤答）、出題（5問・復習混合）、問題データ。

### 背景レイアウトの独立チェック

```sh
xcrun swiftc -parse-as-library doparika/Services/WorldMotionController.swift doparika/Views/WorldSectionLayout.swift tools/check_background_layout.swift -o /tmp/doparika-background-checks
/tmp/doparika-background-checks
```

画面確認の結果と未確認事項は `docs/qa/asset-readiness.md` を参照。
