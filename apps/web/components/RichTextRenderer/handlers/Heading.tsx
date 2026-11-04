import { NodeHandler } from '.'

export const Heading: NodeHandler = (props) => {
  const level = String(props.node.attrs?.level || 1)
  const headingProps = props.node.attrs?.id ? { id: props.node.attrs.id as string, tabIndex: -1 } : {}

  switch (level) {
    case '1':
      return <h1 {...headingProps}>{props.children}</h1>
    case '2':
      return <h2 {...headingProps}>{props.children}</h2>
    case '3':
      return <h3 {...headingProps}>{props.children}</h3>
    case '4':
      return <h4 {...headingProps}>{props.children}</h4>
    case '5':
      return <h5 {...headingProps}>{props.children}</h5>
    case '6':
      return <h6 {...headingProps}>{props.children}</h6>
    default:
      return <h3 {...headingProps}>{props.children}</h3>
  }
}
