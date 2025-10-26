import React, {ReactNode} from 'react'
import {getPageMap} from 'nextra/page-map'
import {Layout, Navbar, Footer} from 'nextra-theme-docs'
import {Head} from 'nextra/components'
import 'nextra-theme-docs/style.css'

export default async function RootLayout({children}: { children: ReactNode }) {
    const pageMap = await getPageMap()

    return (
        <html lang="en" suppressHydrationWarning>
        <Head backgroundColor={{
            dark: 'rgb(15, 23, 42)',
            light: 'rgb(255, 255, 255)'
        }} color={{
            hue: {dark: 120, light: 0},
            saturation: {dark: 100, light: 100}
        }}>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <meta property="og:title" content="Homelab"/>
            <meta property="og:description"
                  content="Production-grade Kubernetes homelab with GitOps, security hardening, and infrastructure automation"/>
        </Head>
        <body>
        <Layout
            pageMap={pageMap}
            navbar={
                <Navbar
                    logo={<div style={{display: 'flex', alignItems: 'center', gap: '8px'}}>
                        <img src="/logo.png" alt="Logo" style={{height: '32px'}}/>
                        <span style={{fontWeight: 'bold'}}>Homelab</span>
                    </div>}
                    projectLink="https://github.com/zengarden-space"
                />
            }
            footer={
                <Footer>
                    {new Date().getFullYear()} © Homelab documentation by Oleksiy Pylypenko
                </Footer>
            }
            docsRepositoryBase="https://gitea.homelab.int.zengarden.space/zengarden-space"
            editLink={null}
            feedback={{content: null}}
            darkMode={false}
            nextThemes={{
                defaultTheme: 'light'
            }}
            navigation={{
                prev: true,
                next: true
            }}
        >
            {children}
        </Layout>
        </body>
        </html>
    )
}