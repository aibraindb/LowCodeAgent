
import React from 'react'
import { ConsolidationPanel } from './consolidation/ConsolidationPanel'
import { Viewer } from './viewer/Viewer'

export const App: React.FC = () => {
  const path = window.location.pathname
  if (path.startsWith('/viewer')) return <Viewer />
  return <ConsolidationPanel />
}
