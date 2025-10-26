# Homelab Platform Engineering Documentation

Comprehensive technical documentation for a production-grade Kubernetes homelab built on Raspberry Pi Compute Module 5 blades.

## Overview

This Nextra-powered documentation site explains the architecture, design decisions, and operational procedures for a sophisticated homelab demonstrating platform engineering best practices.

## Quick Start

### Development

```bash
# Install dependencies
npm install

# Run development server
npm run dev

# Open browser to http://localhost:3000
```

### Build

```bash
# Build static site
npm run build

# Preview production build
npm run start
```

### Export

```bash
# Generate static HTML
npm run export

# Output in .next/out/
```

## Structure

```
docs/
├── pages/
│   ├── index.mdx                      # Landing page
│   ├── introduction/                  # Philosophy and vision
│   ├── hardware/                      # Hardware architecture
│   ├── networking/                    # Network design
│   ├── infrastructure/                # Ansible and K3s
│   ├── core-components/               # Platform services
│   ├── automation/                    # Custom operators
│   ├── gitops/                        # CI/CD pipeline
│   ├── operations/                    # Ops guide
│   └── images/                        # Diagrams and screenshots
├── theme.config.jsx                   # Nextra theme configuration
├── next.config.mjs                    # Next.js configuration
├── package.json                       # Dependencies
└── README.md                          # This file
```

## Key Features

### Covered Topics

- ✅ **Philosophy**: Why build a homelab, design principles
- ✅ **Hardware**: CM5 blades, NVMe storage, power efficiency
- ✅ **Networking**: VLANs, DNS zones, VPN access
- ✅ **Infrastructure**: Ansible automation, K3s hardening
- ✅ **Core Components**: MetalLB, cert-manager, ingress, external-dns
- ✅ **Custom Operators**: DerivedSecrets, Metabase CNPG automation
- ✅ **GitOps**: Gitea, ArgoCD, deployment pipeline
- ✅ **Operations**: Common tasks, troubleshooting, monitoring

### Documentation Features

- 📖 **Code snippets** from actual configuration files
- 🔐 **Security considerations** for each component
- 🎯 **Design rationale** explaining technical decisions
- 🛠️ **Troubleshooting guides** with common issues
- 📊 **Comparison tables** for alternatives considered
- 💡 **Best practices** from real operational experience

## Deployment

### Local Hosting

```bash
npm run build && npm run start
```

### Static Export

```bash
npm run export
# Deploy .next/out/ to any static hosting (GitHub Pages, Netlify, Vercel, S3, etc.)
```

### Docker Deployment (Optional)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm run export

FROM nginx:alpine
COPY --from=builder /app/.next/out /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Contributing

### Adding New Pages

1. Create `.mdx` file in appropriate `pages/` subdirectory
2. Update `_meta.json` for navigation
3. Add code snippets from real configuration files
4. Include troubleshooting section
5. Test locally with `npm run dev`

### Adding Diagrams

1. Create diagram using tools in `pages/images/.gitkeep`
2. Export as PNG or SVG
3. Place in `public/images/` or `pages/images/`
4. Reference in MDX: `![Description](./images/diagram.png)`
5. Add alt text for accessibility

### Style Guidelines

- **Code blocks**: Include language for syntax highlighting
- **File paths**: Show absolute paths from repository root
- **Commands**: Prefix with `$` for shell, `#` for comments
- **Emphasis**: Use **bold** for important terms, *italic* for emphasis
- **Links**: Use relative links for internal pages

## Technology Stack

- **Next.js**: React framework for static site generation
- **Nextra**: Documentation framework with MDX support
- **React**: UI library
- **TypeScript/JSX**: Component configuration

## License

MIT - See repository LICENSE file

## Contact

- **Author**: Oleksiy Pylypenko
- **GitHub**: https://github.com/zengarden-space/
- **Gitea**: https://gitea.homelab.int.zengarden.space/zengarden-space/
