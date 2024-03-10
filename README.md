# AI Translate

This is a small, simple, utility that parses an Xcode `.xcstrings` file, asks ChatGPT to translate each entry, and then saves the results back in the `xcstrings` JSON format.

I have found that, while much cheaper than GPT4, GPT3.5 does not provide satisfactory results. Even with GPT4 (which is the hardcoded default used by this tool) I strongly recommend having translations tested by a qualified human as this tool will almost certainly not produce perfect results.

## Missing Features

This tools supports all the features that I currently use personally, which are not all of the features supported by `xcstrings`. Pull requests are welcome to add those missing features.

## Usage

Simply pull this repo, then run the command:

```
swift run ai-translate /path/to/your/Localizable.xcstrings -o <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB
```

Help output:

```
  USAGE: ai-translate <input-file> --languages <languages> --open-ai-key <open-ai-key> [--verbose] [--skip-backup] [--force]

  ARGUMENTS:
    <input-file>

  OPTIONS:
    -l, --languages <languages>
    -o, --open-ai-key <open-ai-key>
                            Your OpenAI API key, see: https://platform.openai.com/api-keys
    -v, --verbose
    -s, --skip-backup       By default a backup of the input will be created. When this flag is provided, the backup is skipped.
    -f, --force             Forces all strings to be translated, even if an existing translation is present.
    -h, --help              Show help information.
```
