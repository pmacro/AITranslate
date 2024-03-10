# AITranslate

This is a small, simple, utility that parses an Xcode `.xcstrings` file, asks ChatGPT to translate each entry, and then saves the results back in the `xcstring` JSON format.

I have found that, while much cheaper than GPT4, GPT3.5 does not provide satisfactory results. Even with GPT4 (which is the hardcoded default used by this tool) I strongly recommend having translations tested as it will almost certainly not produce perfect results.

## Usage

Simply pull this repo, then run the command:

```
swift run ai-translate /path/to/your/Localizable.xcstrings -a <your-openai-API-key> -v -l de,es,fr,he,it,ru,hi,en-GB
```
