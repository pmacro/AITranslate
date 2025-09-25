# AI Translate

This is a small, simple, utility that parses an Xcode `.xcstrings` file, asks ChatGPT to translate each entry, and then saves the results back in the `xcstrings` JSON format.

This tool is hardcoded to use ChatGPT-4. While ChatGPT3.5 is significantly less expensive, it does not provide satisfactory results. Selecting a model via a command-line flag has been deliberately omitted for this reason, thus ensuring this tool does not contribute to a proliferation of poor translations in apps on Apple platforms.  

Please note that is **very strongly** recommend to have translations tested by a qualified human as even ChatGPT-4 will almost certainly not produce perfect results.

## Missing Features

This tool supports all the features that I currently use personally, which are not all of the features supported by `xcstrings` (for example, I have not tested plural strings, or strings that vary by device). Pull requests are welcome to add those missing features.

## Install

```bash
## install or update
curl -fsSL https://raw.githubusercontent.com/kimliss/fork-AITranslate/refs/heads/main/install.sh | bash
## uninstall 
curl -fsSL https://raw.githubusercontent.com/kimliss/fork-AITranslate/refs/heads/main/install.sh | bash install.sh uninstall
```

## Usage

Run the following command from the repo root folder:

```bash
## use common args
ai-translate /path/to/your/Localizable.xcstrings -o <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB
## use env config
curl -o .env https://raw.githubusercontent.com/kimliss/fork-AITranslate/refs/heads/main/.env.example
echo ".env" >> .gitignore
ai-translate /path/to/your/Localizable.xcstrings
```

Help output:

```
  USAGE: ai-translate <input-file> [--languages <languages>] [--open-ai-key <open-ai-key>] [--host <host>] [--model <model>] [--verbose] [--skip-backup] [--force]

  ARGUMENTS:
    <input-file>

  OPTIONS:
    -l, --languages <languages>
                            A comma separated list of language codes (must match the language codes used by xcstrings)
    -o, --open-ai-key <open-ai-key>
                            Your OpenAI API key, see: https://platform.openai.com/api-keys
    --host <host>           Your OpenAI Proxy Host
    -m, --model <model>     Your Model, see: https://platform.openai.com/docs/models, e,g (gpt-3.5-turbo, gpt-4o-mini, gpt-4o)
    -v, --verbose
    -s, --skip-backup       By default a backup of the input will be created. When this flag is provided, the backup is skipped.
    -f, --force             Forces all strings to be translated, even if an existing translation is present.
    -h, --help              Show help information.
```
