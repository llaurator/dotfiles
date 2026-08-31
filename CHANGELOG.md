# Changelog

Cambios generados automáticamente a partir de Conventional Commits.

## [1.4.1](https://github.com/llaurator/dotfiles/compare/v1.4.0...v1.4.1) (2026-08-31)

### 🐛 Fixes

* **config:** preserve preexisting local settings ([8251ad7](https://github.com/llaurator/dotfiles/commit/8251ad70467e9d4de51553b48b4d99cb8f1ac744))
* **fonts:** reuse existing MesloLGS Nerd Font ([3ef6ae5](https://github.com/llaurator/dotfiles/commit/3ef6ae548618e4d9c72523f2bb75a9163a5beb7a))
* **installer:** improve bootstrap and preflight safety ([29dd80e](https://github.com/llaurator/dotfiles/commit/29dd80ea1c2e8e717717737feb0146f40ec1c987))
* **rollback:** recover interrupted package transactions ([230a89b](https://github.com/llaurator/dotfiles/commit/230a89bc334f6b000db03ca0ff942ad107638dde))
* **vscode:** merge managed JSONC values minimally ([65319f5](https://github.com/llaurator/dotfiles/commit/65319f5b42c26e7a76cdf5126fa59f875a6187f3))
* **vscode:** preserve JSONC formatting during merge ([5cb4631](https://github.com/llaurator/dotfiles/commit/5cb463192700096d771572efb23fbd4d52ea0401))
* **zsh:** reuse resolved components during install ([584c751](https://github.com/llaurator/dotfiles/commit/584c751735c776eb028b8cec0577a6a8f392d642))

### ♻️ Refactoring

* **zsh:** resolve existing components safely ([5760eb1](https://github.com/llaurator/dotfiles/commit/5760eb1ff9720a971cf7fa972f733c61e992883c))

## [1.4.0](https://github.com/llaurator/dotfiles/compare/v1.3.0...v1.4.0) (2026-08-30)

### ✨ Features

* **konsole:** add optional Dracula profile ([c741022](https://github.com/llaurator/dotfiles/commit/c7410229a35bbfc3076db4febc7768cad6e5b7a7))

### 📚 Documentation

* add terminal setup screenshot ([622faf2](https://github.com/llaurator/dotfiles/commit/622faf240c9a79a3ffa9b4049efc21ab8b7f2c09))

## [1.3.0](https://github.com/llaurator/dotfiles/compare/v1.2.0...v1.3.0) (2026-08-30)

### ✨ Features

* **terminal:** install MesloLGS Nerd Font ([45fff3d](https://github.com/llaurator/dotfiles/commit/45fff3d2cfa1d3d97246ceb9858b7245b0ddab34))
* **vscode:** add opt-in install and Spanish locale ([1b4e7af](https://github.com/llaurator/dotfiles/commit/1b4e7af57ec7530c8ddc9d3d0ad9051ae437dfb8))

### 🐛 Fixes

* **installer:** initialize platform for uninstall ([615d70b](https://github.com/llaurator/dotfiles/commit/615d70b8661fa4be1685a924cba4e19c90dd40f7))
* **installer:** make package snapshots locale independent ([78c2cb4](https://github.com/llaurator/dotfiles/commit/78c2cb492ccc6586868bbb9c7120a79c8cd5c1c0))
* **installer:** restore system state on uninstall ([ddb9476](https://github.com/llaurator/dotfiles/commit/ddb9476ec0604c34e568ed51c9ca8214adcce910))
* **installer:** resume interrupted restores ([8953c28](https://github.com/llaurator/dotfiles/commit/8953c28dab8c48aacb321de56bf361d14ea82964))
* **installer:** track package transaction dependencies ([8ac8e13](https://github.com/llaurator/dotfiles/commit/8ac8e134adc2bdfc567415216397d8219338377e))

### 📚 Documentation

* prepare repository for public use ([9111e3c](https://github.com/llaurator/dotfiles/commit/9111e3c60c2f60dd3132d858df5cc2cfc688bcc6))

### ♻️ Refactoring

* **installer:** consolidate privilege prompts ([b47971f](https://github.com/llaurator/dotfiles/commit/b47971ff48aa63c2d299e55d05d412fdd821686d))

### ⚡ Performance

* **terminal:** reduce Nerd Font download size ([c802ecc](https://github.com/llaurator/dotfiles/commit/c802ecc6ae6a942ded1b4c8026e8c8d0dbbab09d))

## [1.2.0](https://github.com/llaurator/dotfiles/compare/v1.1.0...v1.2.0) (2026-08-30)

### ✨ Features

* **bootstrap:** add one-command remote installation ([c6653f8](https://github.com/llaurator/dotfiles/commit/c6653f8ee103cf6461aa44d3564024a5ffb77433))
* **installer:** add reversible dotfiles installation ([3cae681](https://github.com/llaurator/dotfiles/commit/3cae681f42e0a4ee60133ef4e2f2fc51d8e77896))

## [1.1.0](https://github.com/llaurator/dotfiles/compare/v1.0.0...v1.1.0) (2026-08-30)

### ✨ Features

* **history:** add Bash to Zsh history migration ([a24fcc8](https://github.com/llaurator/dotfiles/commit/a24fcc84da9f5b7859e0e2c525f413e406318219))

## 1.0.0 (2026-08-28)

### ✨ Features

* **git:** add machine-local identity include ([a9f049a](https://github.com/llaurator/dotfiles/commit/a9f049ac2b4c8b5a7d0b75117ed5450e9cbd7b4a))
* **installer:** add safe cross-platform bootstrap ([76b62bb](https://github.com/llaurator/dotfiles/commit/76b62bbc85363d3e7f378202b920e596ba2b5fc6))
* **ssh:** clarify local host configuration ([a62c46e](https://github.com/llaurator/dotfiles/commit/a62c46e32e6c7e21d1115f4bb0f742e2c6c6fea5))
* **ssh:** keep client templates host-agnostic ([414d0af](https://github.com/llaurator/dotfiles/commit/414d0af2dcd677bf7f922edb79b83bbcc88e4bfe))
* **vscode:** add minimal shared editor setup ([3a933ba](https://github.com/llaurator/dotfiles/commit/3a933ba1ca59595ea5b0eab38489f60631d4899c))
* **vscode:** add Python Environments extension ([ae07f9d](https://github.com/llaurator/dotfiles/commit/ae07f9d50a8ee579f629cfc3f76c6eb96af067b5))
* **vscode:** add Python Environments extension ([f1af542](https://github.com/llaurator/dotfiles/commit/f1af542c9ad5215aa6ea2e6a19b08394d47f0460))

### 🐛 Fixes

* **ci:** grant semantic-release GitHub permissions ([54f5ff7](https://github.com/llaurator/dotfiles/commit/54f5ff7773e37744a3ab9ae8c15da51d6530796e))
* **git:** detect existing local identity correctly ([c9bec68](https://github.com/llaurator/dotfiles/commit/c9bec685ca9af41d471be0719ce6d385a2d9d3fa))
* **vscode:** avoid unchanged settings rewrites ([337e276](https://github.com/llaurator/dotfiles/commit/337e2764b239e68e1fbe0a66b9decbcb166d0fdd))
* **vscode:** safely merge managed settings ([189878a](https://github.com/llaurator/dotfiles/commit/189878a71017dbbc7201135d65c18f1878352f7f))

### 📚 Documentation

* document installation and safe migration ([c3f5b10](https://github.com/llaurator/dotfiles/commit/c3f5b105400cb34d9051f0dfb071865048c3506f))
* document managed VS Code settings ([426c6e7](https://github.com/llaurator/dotfiles/commit/426c6e783ee415854580233b653b50326f0d3fa0))

### ♻️ Refactoring

* **zsh:** organize portable profile configuration ([2e27154](https://github.com/llaurator/dotfiles/commit/2e27154192a15ea975aa3887dbff6e92cf34411e))

### 🧹 Chores

* **release:** automate changelog and GitHub releases ([1d4c07b](https://github.com/llaurator/dotfiles/commit/1d4c07b95decba151d3cc6636aa8ffc1f61de36e))
* **repo:** harden local secrets exclusions ([0fbaff2](https://github.com/llaurator/dotfiles/commit/0fbaff2e8a494eaad63e91028d34b3b63dd59fd4))

### ⏪ Reverts

* **vscode:** keep the minimal extension set ([ad04714](https://github.com/llaurator/dotfiles/commit/ad047148c64e462bf3d76783ea5020b5c9b0597c))
