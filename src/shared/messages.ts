
export type ReadyMsg = { kind: 'READY'; viewerId: string }
export type LoadDocMsg = { kind: 'LOAD_DOC'; base: string; docType: string; pdfUrl: string; jsonUrl: string }
export type HighlightMsg = { kind: 'HIGHLIGHT_FIELD'; base: string; bbox: [number,number,number,number] }
export type PingMsg = { kind: 'PING' } | { kind: 'PONG' }
export type AnyMsg = ReadyMsg | LoadDocMsg | HighlightMsg | PingMsg
