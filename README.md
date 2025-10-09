
# Inter-window Document Demo (React + Vite)

- Open documents in **separate browser tabs** per *docType* (invoice/lease/fds/…).
- **Consolidation Panel** loads multiple PDF/JSON pairs, previews JSON, and on click asks the Viewer to **highlight** the bbox.
- Uses `window.open(name)` to reuse a tab for the same docType and `postMessage` for secure messaging.

## Run
```bash
npm i
npm run dev
# open http://localhost:5173
```

## Test
1. Click **Choose Files**, select multiple PDFs and their matching JSONs.
2. In the left list, click **Open** to open/attach a Viewer tab for that docType.
3. Click **JSON** to preview the DocAI JSON in the panel; click a node to highlight its bbox in the Viewer tab.

> This demo uses the browser PDF viewer via `<iframe>`; for production accuracy, plug in your existing `PdfCanvas` and map normalized vertices precisely to PDF page coordinates.
