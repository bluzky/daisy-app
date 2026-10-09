import { syntaxTree } from "@codemirror/language"

export function formattingState(state) {
  const selection = state.selection.main
  const commands = new Set()
  let heading = 0
  for (let node = syntaxTree(state).resolveInner(selection.from, 1); node; node = node.parent) {
    if (node.to < selection.to) continue
    const match = /^(?:ATX|Setext)Heading([1-6])$/.exec(node.name)
    if (match) heading = Number(match[1])
    const command = { StrongEmphasis: 'bold', Emphasis: 'italic',
      Strikethrough: 'strikethrough', Highlight: 'highlight', Link: 'link', InlineCode: 'code',
      BulletList: 'list', OrderedList: 'list', Blockquote: 'quote',
      FencedCode: 'fenced', CodeBlock: 'plain', Table: 'table' }[node.name]
    if (command) commands.add(command)
  }
  return { heading, commands: [...commands].sort() }
}
