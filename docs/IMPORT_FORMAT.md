# Hope's Voice board import format — `bestwishes.board/v1`

One JSON file describes one child's whole setup. The format spec is public (it can go in the repo).
A real child's file is private family data: it never goes in git. It's loaded on-device
(caregiver mode → Import) or from a private store.

## Top level
```json
{
  "format": "bestwishes.board/v1",
  "source": "proloquo2go-manual-transcription",   // free text: where it came from
  "profile": { ... },
  "boards": [ ... ]
}
```

## profile
```json
{
  "displayName": "Child 1",
  "homeBoard": "home",                 // board id shown at launch
  "grid": { "rows": 6, "cols": 8 },    // default grid; a board can override
  "voice": { "engine": "system|server", "voiceId": "en-US-…", "rate": 1.0, "pitch": 1.0 },
  "messageBar": {
    "enabled": true,
    "speakOnTap": true,                // speak each button as it's tapped
    "speakOnBarTap": true,             // tap bar = speak whole sentence
    "clearAfterSpeak": false
  },
  "folderBehavior": { "returnHomeAfterSelection": false },
  "colorScheme": "fitzgerald",         // or "custom" with "colors" below
  "colors": { "noun": "#FFD966", "verb": "#93C47D", "adjective": "#6FA8DC",
              "pronoun": "#FFE599", "social": "#F4CCCC", "misc": "#FFFFFF" },
  "coreRow": ["i","want","more","help","stop","go"]   // optional sticky row (cell ids)
}
```

## boards[]
```json
{
  "id": "home",
  "title": "Home",
  "rows": 6, "cols": 8,               // optional override of profile.grid
  "cells": [ ... ]
}
```

## cells[] — one per occupied grid position (empty positions are just omitted)
```json
{
  "id": "want",
  "row": 0, "col": 1,                 // 0-based, top-left origin; positions must match the source exactly
  "type": "word",                     // word | folder | action
  "label": "want",                    // text shown under the picture
  "speak": "I want",                  // optional; what's said if different from label
  "pos": "verb",                      // drives background color under fitzgerald scheme
  "bg": "#93C47D",                    // optional explicit override
  "border": "#000000",                // optional
  "image": { "source": "generate", "prompt": "child pointing at toy" },
            // source: generate (server makes an original picture from label/prompt)
            //       | file (private image path/URL, e.g. a family photo)
            //       | none (text-only button)
  "target": "food",                   // folder cells: id of board to open
  "action": null,                     // action cells: back | home | clear | delete-last | speak-bar
  "addToMessage": true,               // false = speaks but doesn't go in the message bar
  "hidden": false                     // kept in layout but not shown (P2G-style hide)
}
```

## Rules
- Exact position (board, row, col) is the contract: the kid's motor memory depends on it.
- Unknown fields are kept under `"extra"` and ignored, so transcriptions can carry notes.
- Proprietary symbols (e.g. SymbolStix) are never copied in. Pictures default to `generate`
  (original xAI picture from the server), or `file` for family photos.
- Validation on import: unique ids, no two cells in one position, every `target` exists,
  every board fits its grid. Errors are listed, nothing is half-imported.
