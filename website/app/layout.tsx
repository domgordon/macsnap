import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'MacSnap - Window Snapping for macOS',
  description: 'Windows-style window snapping for macOS. Use keyboard shortcuts to snap windows to halves, quarters, and move between monitors.',
  keywords: ['macOS', 'window manager', 'window snapping', 'productivity', 'Mac app'],
  authors: [{ name: 'MacSnap' }],
  openGraph: {
    title: 'MacSnap - Window Snapping for macOS',
    description: 'Windows-style window snapping for macOS. Snap windows with keyboard shortcuts.',
    type: 'website',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="antialiased">
        {children}
      </body>
    </html>
  )
}
