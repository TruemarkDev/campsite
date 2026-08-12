import { NodeHandler } from '.'

export const Table: NodeHandler = ({ children, node }) => {
  const columnWidths = node.content?.[0]?.content?.flatMap((cell) => {
    const colspan = Number(cell.attrs?.colspan || 1)
    const widths = cell.attrs?.colwidth as number[] | null | undefined

    return widths?.length ? widths : Array<null>(colspan).fill(null)
  })

  return (
    <div className='rich-text-table-wrapper'>
      <table className='rich-text-table'>
        {columnWidths && (
          <colgroup>
            {columnWidths.map((width, index) => (
              // eslint-disable-next-line react/no-array-index-key
              <col key={index} style={width ? { width: `${width}px` } : undefined} />
            ))}
          </colgroup>
        )}
        <tbody>{children}</tbody>
      </table>
    </div>
  )
}

export const TableRow: NodeHandler = ({ children }) => <tr>{children}</tr>

export const TableHeader: NodeHandler = ({ children }) => <th scope='col'>{children}</th>

export const TableCell: NodeHandler = ({ children }) => <td>{children}</td>
