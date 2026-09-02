# Homelab Documentation Site

Technical documentation for the homelab platform, built with Nextra.

## Development

```bash
npm install
npm run dev  # http://localhost:3000
```

## Build

```bash
npm run build            # static export into ./out (no base path)
```

The site is a static export (`output: 'export'`). Search is indexed by Pagefind
in the `postbuild` step, so always run `npm run build` rather than `next build`.

## Deployment

Deployed to GitHub Pages by `.github/workflows/docs-pages.yml` on every push to
`main` that touches `docs/`: https://oleksiyp.github.io/homelab

Because it is a project site served from a subdirectory, the workflow builds with
`NEXT_PUBLIC_BASE_PATH=/homelab`. To reproduce a production build locally:

```bash
NEXT_PUBLIC_BASE_PATH=/homelab npm run build
npx serve out  # then open http://localhost:3000/homelab
```

Absolute asset paths written by hand (plain `<img>`, `unoptimized` `next/image`)
are **not** rewritten by Next.js — prefix them with `NEXT_PUBLIC_BASE_PATH`.
