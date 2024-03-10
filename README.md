# AITranslate

This is a small utility that parses an `.xcstrings` file, asks ChatGPT to translate each entry, and then saves the results back in the `xcstring` JSON format.

## Usage

Simply pull this repo, then run the command:

```
swift run ai-translate /path/to/your/Localizable.xcstrings -a <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB
```
