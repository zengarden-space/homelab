import nextra from 'nextra'

// GitHub Pages serves this project site from https://oleksiyp.github.io/homelab,
// so every asset/route needs the `/homelab` prefix. Left empty for local dev.
const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? ''

// Set up Nextra with its configuration
const withNextra = nextra({

})

// Export the final Next.js config with Nextra included
export default withNextra({
    output: 'export',
    basePath,
    trailingSlash: true,
    images: {
        unoptimized: true,
    },
})
