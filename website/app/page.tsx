import Image from 'next/image'

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col">
      {/* Hero Section */}
      <section className="flex-1 flex flex-col items-center justify-center px-6 py-20">
        <div className="max-w-2xl mx-auto text-center">
          {/* App Icon */}
          <div className="mb-8">
            <Image
              src="/icon.png"
              alt="MacSnap icon"
              width={128}
              height={128}
              className="mx-auto rounded-[28px] shadow-lg"
              priority
            />
          </div>

          {/* App Name */}
          <h1 className="text-5xl font-semibold tracking-tight text-gray-900 dark:text-white mb-4">
            MacSnap
          </h1>

          {/* Tagline */}
          <p className="text-xl text-gray-600 dark:text-gray-400 mb-10">
            Windows-style window snapping for macOS
          </p>

          {/* Download Button */}
          <a
            href="https://github.com/domgordon/macsnap/releases/latest/download/MacSnap.dmg"
            className="inline-flex items-center gap-3 bg-gray-900 dark:bg-white text-white dark:text-gray-900 px-8 py-4 rounded-xl text-lg font-medium hover:bg-gray-800 dark:hover:bg-gray-100 transition-colors shadow-lg hover:shadow-xl"
          >
            <AppleIcon />
            Download for Mac
          </a>

          {/* System Requirements */}
          <p className="mt-4 text-sm text-gray-500 dark:text-gray-500">
            Requires macOS 12.0 (Monterey) or later
          </p>
        </div>
      </section>

      {/* Features Section */}
      <section className="bg-gray-50 dark:bg-gray-900/50 py-20 px-6">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-2xl font-semibold text-center text-gray-900 dark:text-white mb-12">
            Simple keyboard shortcuts.
          </h2>

          <div className="grid md:grid-cols-3 gap-8">
            <FeatureCard
              icon={<KeyboardIcon />}
              title="Keyboard-First"
              description="Snap windows with Control + Option + Arrow keys."
            />
            <FeatureCard
              icon={<GridIcon />}
              title="Smart Layout"
              description="After snapping, choose from your other windows to complete the layout."
            />
            <FeatureCard
              icon={<MenuBarIcon />}
              title="Menu Bar App"
              description="Runs silently in your menu bar. Launch at login."
            />
          </div>

          {/* Keyboard Shortcuts Preview */}
          <div className="mt-16 bg-white dark:bg-gray-800 rounded-2xl p-8 shadow-sm">
            <h3 className="text-lg font-medium text-gray-900 dark:text-white mb-6 text-center">
              Keyboard Shortcuts
            </h3>
            <div className="grid sm:grid-cols-2 gap-4 text-sm">
              <ShortcutRow keys={['⌃', '⌥', '←']} action="Snap left half" />
              <ShortcutRow keys={['⌃', '⌥', '→']} action="Snap right half" />
              <ShortcutRow keys={['⌃', '⌥', '↑']} action="Snap top half" />
              <ShortcutRow keys={['⌃', '⌥', '↓']} action="Snap bottom half" />
              <ShortcutRow keys={['⌃', '⌥', '↵']} action="Maximize window" />
              <div className="flex items-center justify-center py-2 px-4 rounded-lg bg-gray-50 dark:bg-gray-700/50">
                <span className="text-gray-500 dark:text-gray-400 text-xs">+ more quarter & combo shortcuts</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-6 text-center text-sm text-gray-500 dark:text-gray-500">
        <div className="flex items-center justify-center gap-4">
          <a
            href="https://github.com/domgordon/macsnap"
            className="hover:text-gray-900 dark:hover:text-gray-300 transition-colors"
          >
            GitHub
          </a>
          <span>·</span>
          <span>MIT License</span>
        </div>
      </footer>
    </main>
  )
}

// Components

function FeatureCard({
  icon,
  title,
  description,
}: {
  icon: React.ReactNode
  title: string
  description: string
}) {
  return (
    <div className="text-center">
      <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 mb-4">
        {icon}
      </div>
      <h3 className="text-lg font-medium text-gray-900 dark:text-white mb-2">
        {title}
      </h3>
      <p className="text-gray-600 dark:text-gray-400 text-sm">
        {description}
      </p>
    </div>
  )
}

function ShortcutRow({ keys, action }: { keys: string[]; action: string }) {
  return (
    <div className="flex items-center justify-between py-2 px-4 rounded-lg bg-gray-50 dark:bg-gray-700/50">
      <div className="flex items-center gap-1">
        {keys.map((key, i) => (
          <span key={i}>
            <kbd className="inline-flex items-center justify-center min-w-[28px] h-7 px-2 bg-white dark:bg-gray-600 rounded border border-gray-200 dark:border-gray-500 text-xs font-medium text-gray-700 dark:text-gray-200 shadow-sm">
              {key}
            </kbd>
            {i < keys.length - 1 && <span className="mx-0.5 text-gray-400">+</span>}
          </span>
        ))}
      </div>
      <span className="text-gray-600 dark:text-gray-400">{action}</span>
    </div>
  )
}

// Icons

function AppleIcon() {
  return (
    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  )
}

function KeyboardIcon() {
  return (
    <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M6.75 7.5l3 2.25-3 2.25m4.5 0h3m-9 8.25h13.5A2.25 2.25 0 0021 18V6a2.25 2.25 0 00-2.25-2.25H5.25A2.25 2.25 0 003 6v12a2.25 2.25 0 002.25 2.25z" />
    </svg>
  )
}

function GridIcon() {
  return (
    <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z" />
    </svg>
  )
}

function MenuBarIcon() {
  return (
    <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 5.25h16.5M3.75 5.25v.75a.75.75 0 00.75.75h14.25a.75.75 0 00.75-.75v-.75M3.75 5.25a.75.75 0 01.75-.75h14.25a.75.75 0 01.75.75" />
      <circle cx="17" cy="5.25" r="1" fill="currentColor" />
      <circle cx="14" cy="5.25" r="1" fill="currentColor" />
      <circle cx="11" cy="5.25" r="1" fill="currentColor" />
    </svg>
  )
}
