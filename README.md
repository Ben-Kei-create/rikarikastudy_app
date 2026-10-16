# ドパリカ!

問題で世界をうごかす理科クイズ iOS アプリ (Swift / SwiftUI / SwiftData)。
元ネタ: [rikarikastudy](https://github.com/Ben-Kei-create/rikarikastudy)

## 構成
- `doparika/Models` — Question (JSON) / SwiftData モデル
- `doparika/Services` — QuizEngine, QuestionSelector(復習ミックス), LevelCalculator, WorldMotionController, CollectionService ほか
- `doparika/Views` — Home / Quiz / Result / Collection、手続き型の地層背景 (`WorldBackgroundView`)
- `doparika/Resources/questions_mountain.json` — 山ステージ問題 (ID は一度発行したら不変)
- `tools/build_questions.py` — rikarikastudy の choice4 問題を 2 択に変換 (既存ファイルがあると再生成を拒否)

## 初回リリース仕様
Lv.1〜30 / 山・地層 / 2択 / 1セッション5問 / 制限時間15秒 / 正解 +20XP
