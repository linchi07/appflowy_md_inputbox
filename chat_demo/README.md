# Markdown + LaTeX Lab

Desktop experiment for the Obsidian-style Markdown input component.

## Run

Use profile mode when evaluating scrolling and formula rendering performance:

```sh
flutter run -d macos --profile
```

The toolbar switches between live editing and pure preview. The stress-sample
menu can load documents containing 100 or 500 rows with two formulas per row.
The right panel reports average build and raster durations for the most recent
120 frames. Scroll the document, then switch modes to refresh the displayed
sample.

Pure preview uses a lazily built list and disables editing, keyboard, selection,
and automatic scrolling services.
