# AI Translate

This is a small, simple, utility that parses an Xcode `.xcstrings` file, asks ChatGPT to translate each entry, and then saves the results back in the `xcstrings` JSON format.

This tool is hardcoded to use GPT-5 mini. Selecting a model via a command-line flag has been deliberately omitted to ensure this tool does not contribute to a proliferation of poor translations in apps on Apple platforms.

Please note that is **very strongly** recommended to have translations tested by a qualified human as even frontier models will almost certainly not produce perfect results.

## Missing Features

This tool supports all the features that I currently use personally, which are not all of the features supported by `xcstrings` (for example, I have not tested plural strings, or strings that vary by device). Pull requests are welcome to add those missing features.

## Usage

Simply pull this repo, then run the following command from the repo root folder:

```
swift run ai-translate /path/to/your/Localizable.xcstrings -o <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB
```

Help output:

```
  USAGE: ai-translate <input-file> --languages <languages> --open-ai-key <open-ai-key> [--verbose] [--skip-backup] [--force] [--match-xcode-ordering] [--no-tui]

  ARGUMENTS:
    <input-file>

  OPTIONS:
    -l, --languages <languages> A comma separated list of language codes (must match the language codes used by xcstrings)
    -o, --open-ai-key <open-ai-key>
                            Your OpenAI API key, see: https://platform.openai.com/api-keys
    -v, --verbose
    -s, --skip-backup       By default a backup of the input will be created. When this flag is provided, the backup is skipped.
    -f, --force             Forces all strings to be translated, even if an existing translation is present.
    --match-xcode-ordering  Sort JSON keys to match Xcode's xcstrings ordering.
    --no-tui                Disable the rich terminal UI and use simple text output instead.
    -h, --help              Show help information.
```
