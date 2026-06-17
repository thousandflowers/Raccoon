# Homebrew Tap Setup — thousandflowers/homebrew-raccoon

## Repo structure

Create a new repo `thousandflowers/homebrew-raccoon` on GitHub (public).

```
homebrew-raccoon/
├── README.md
├── Formula/
│   └── rcc.rb           # Homebrew formula (auto-updated by release workflow)
└── .gitignore
```

## Step-by-step

### 1. Create the tap repo

```bash
# Via gh CLI
gh repo create thousandflowers/homebrew-raccoon --public --description "Homebrew tap for Raccoon (rcc)"

# Or via GitHub UI: New repository → "homebrew-raccoon" → Public
```

### 2. Add initial files

```bash
git clone https://github.com/thousandflowers/homebrew-raccoon.git
cd homebrew-raccoon

mkdir -p Formula

# Copy the formula reference from the main repo
cp path/to/Raccoon/docs/homebrew/Formula/rcc.rb Formula/

# Compute the real SHA256 for the current release
TAG="v0.8.0"
SHA=$(curl -sL "https://github.com/thousandflowers/Raccoon/archive/refs/tags/${TAG}.tar.gz" | shasum -a 256 | cut -d' ' -f1)
sed -i '' 's/PLACEHOLDER_AUTO_UPDATED_BY_RELEASE_WORKFLOW/'"$SHA"'/' Formula/rcc.rb

git add .
git commit -m "Initial tap: rcc v0.8.0"
git push
```

### 3. Test the formula locally

```bash
brew tap thousandflowers/raccoon
brew install rcc
rcc --version
brew test rcc
```

### 4. Set up the PAT for auto-updates

The release workflow in the main repo (`Raccoon/.github/workflows/release.yml`) needs a Personal Access Token to push formula updates to this tap repo.

**Create a classic PAT:**
- GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
- Scopes: `repo` (full control)
- Copy the token

**Add it as a secret in the Raccoon repo:**
- GitHub → thousandflowers/Raccoon → Settings → Secrets and variables → Actions
- New repository secret: `HOMEBREW_TAP_TOKEN` = the PAT you just created

### 5. Test the workflow

Tag a new release:

```bash
git tag v0.8.1
git push origin v0.8.1
```

The release workflow will:
1. Run CI (shellcheck + bats)
2. Create a GitHub Release with release notes
3. Compute SHA256 of the source tarball
4. Clone the tap repo, update `Formula/rcc.rb` with new version + sha256, commit & push

### 6. Verify installation

```bash
brew upgrade rcc
rcc --version
```
