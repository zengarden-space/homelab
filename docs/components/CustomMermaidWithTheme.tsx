'use client'

import { useEffect, useRef, useState } from 'react'
import { useTheme } from 'next-themes'
import mermaid from 'mermaid'

interface CustomMermaidProps {
    chart: string
    config?: any
}

export function CustomMermaidWithTheme({ chart, config }: CustomMermaidProps) {
    const { theme, resolvedTheme } = useTheme()
    const containerRef = useRef<HTMLDivElement>(null)
    const [svg, setSvg] = useState<string>('')
    const [isInitialized, setIsInitialized] = useState(false)

    // Detect current theme
    const currentTheme = theme === 'system' ? resolvedTheme : theme
    const isDark = currentTheme === 'dark'

    // Light theme configuration
    const lightConfig = {
        startOnLoad: true,
        theme: 'base',
        themeVariables: {
            primaryColor: '#E60028',
            primaryTextColor: '#FFFFFF',
            primaryBorderColor: '#C4001F',
            secondaryColor: '#F5F5F7',
            secondaryTextColor: '#1D1D1F',
            secondaryBorderColor: '#D2D2D7',
            tertiaryColor: '#007AFF',
            tertiaryTextColor: '#FFFFFF',
            tertiaryBorderColor: '#0051D5',
            background: '#FFFFFF',
            mainBkg: '#FFFFFF',
            secondBkg: '#FAFAFA',
            lineColor: '#86868B',
            border1: '#D2D2D7',
            border2: '#E5E5E5',
            textColor: '#1D1D1F',
            noteBkgColor: '#F5F5F7',
            noteTextColor: '#1D1D1F',
            noteBorderColor: '#D2D2D7',
            arrowheadColor: '#1D1D1F',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
            fontSize: '16px',
            nodeBorder: '#D2D2D7',
            clusterBkg: '#F5F5F7',
            clusterBorder: '#D2D2D7',
            actorBkg: '#FFFFFF',
            actorBorder: '#E60028',
            actorTextColor: '#1D1D1F',
            signalColor: '#1D1D1F',
            labelBoxBkgColor: '#F5F5F7',
            activationBkgColor: '#FFF3F4',
            activationBorderColor: '#E60028',
            git0: '#E60028',
            git1: '#007AFF',
            git2: '#34C759',
            git3: '#FF9500',
            git4: '#AF52DE',
            git5: '#FF2D55',
            git6: '#5AC8FA',
            git7: '#FFCC00'
        },
        flowchart: {
            useMaxWidth: true,
            htmlLabels: true,
            curve: 'basis',
            padding: 15
        },
        sequence: {
            useMaxWidth: true,
            mirrorActors: true
        }
    }

    // Dark theme configuration
    const darkConfig = {
        startOnLoad: false,
        theme: 'base',
        themeVariables: {
            primaryColor: '#FF3B30',
            primaryTextColor: '#FFFFFF',
            primaryBorderColor: '#E60028',
            secondaryColor: '#2C2C2E',
            secondaryTextColor: '#F5F5F7',
            secondaryBorderColor: '#48484A',
            tertiaryColor: '#0A84FF',
            tertiaryTextColor: '#FFFFFF',
            tertiaryBorderColor: '#007AFF',
            background: '#1C1C1E',
            mainBkg: '#1C1C1E',
            secondBkg: '#2C2C2E',
            lineColor: '#8E8E93',
            border1: '#48484A',
            border2: '#3A3A3C',
            textColor: '#F5F5F7',
            noteBkgColor: '#2C2C2E',
            noteTextColor: '#F5F5F7',
            noteBorderColor: '#48484A',
            arrowheadColor: '#F5F5F7',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
            fontSize: '16px',
            nodeBorder: '#48484A',
            clusterBkg: '#2C2C2E',
            clusterBorder: '#48484A',
            actorBkg: '#2C2C2E',
            actorBorder: '#FF3B30',
            actorTextColor: '#F5F5F7',
            signalColor: '#F5F5F7',
            labelBoxBkgColor: '#2C2C2E',
            activationBkgColor: '#3A1F1F',
            activationBorderColor: '#FF3B30',
            git0: '#FF3B30',
            git1: '#0A84FF',
            git2: '#30D158',
            git3: '#FF9F0A',
            git4: '#BF5AF2',
            git5: '#FF375F',
            git6: '#64D2FF',
            git7: '#FFD60A'
        },
        flowchart: {
            useMaxWidth: true,
            htmlLabels: true,
            curve: 'basis',
            padding: 15
        },
        sequence: {
            useMaxWidth: true,
            mirrorActors: true
        }
    }

    // Re-initialize when theme changes
    useEffect(() => {
        const activeConfig = isDark ? darkConfig : lightConfig
        const mergedConfig = { ...activeConfig, ...config }
        mermaid.initialize(mergedConfig)
        setIsInitialized(true)
    }, [isDark, config])

    // Render the diagram
    useEffect(() => {
        if (!isInitialized || !chart) return

        const renderDiagram = async () => {
            try {
                const id = `mermaid-${Math.random().toString(36).substr(2, 9)}`
                const { svg: renderedSvg } = await mermaid.render(id, chart)
                setSvg(renderedSvg)
            } catch (error) {
                console.error('Error rendering mermaid diagram:', error)
                setSvg(`<pre style="color: ${isDark ? '#FF375F' : '#FF3B30'}; background: ${isDark ? '#3A1F1F' : '#FFF3F4'}; padding: 1rem; border-radius: 6px; border: 2px solid ${isDark ? '#FF3B30' : '#E60028'};">Error rendering diagram:\n${error}</pre>`)
            }
        }

        renderDiagram()
    }, [chart, isInitialized, isDark])

    return (<>
        <div
            ref={containerRef}
            className="mermaid-wrapper my-6"
            dangerouslySetInnerHTML={{ __html: "test" }}
            style={{
                display: 'flex',
                justifyContent: 'center',
                alignItems: 'center'
            }}
        /></>
    )
}