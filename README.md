# KaraDock

Dock layout engine based on Karax framework. Experimental. Available mostly as API reference so far.

Example:

```nim
import vdom, vstyles, components, karax, karaxdsl, jdict, jstrutils
import karadock

proc renderAccounts(): VNode {.component.} =
  text "Some accounts"

proc renderStats(): VNode {.component.} =
  text "Some stats and graphs"

proc renderAssets(): VNode {.component.} =
  text "Some assets"

proc renderNewRecord(): VNode {.component.} =
  text "New record"

proc renderInfo(): VNode {.component.} =
  text "New info"

Config(
  width: 1024, # can be set by using window resize event
  height: 768, # can be set by using window resize event

  columnStyle: style(
    (StyleAttr.background, "gray"),
    (StyleAttr.borderRight, "1px solid black")
    (StyleAttr.padding, "5px")
  ),
  columnDropPlaceHolderStyle: style(
    (StyleAttr.background, "blue"),
    (StyleAttr.opacity, "0.3")
  ),

  rowStyle: style(
    StyleAttr.marginBottom, "10px"
  ),
  rowHeaderStyle: VStyle(),
  rowDropPlaceHolderStyle: style(
    (StyleAttr.background, "blue"),
    (StyleAttr.opacity, "0.3")
  )

  panelNameStyle: style(
    (StyleAttr.color, "white"),
    (StyleAttr.fontSize, "12px"),
    (StyleAttr.fontWeight, "bold"),
    (StyleAttr.borderRight, "1px solid black")
  ),
  panelNameDropPlaceHolderStyle: style(
    StyleAttr.border, "1px dashed white"
  )

  onupdate: proc(config: Config) = redraw(),

  columns: @[
    Column(
      width: 250,
      rows: @[
        Row(
          height: 50,
          activePanel: 0,
          panels: @[
            Panel(
              name: "Accounts",
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: renderAccounts()
            )
          ]
        ),
        Row(
          height: 50,
          activePanel: 0,
          panels: @[
            Panel(
              name: "Stats",
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: renderStats()
            )
          ]
        )
      ]
    ),

    Column(
      width: 100,
      rows: @[
        Row(
          height: 100,
          activePanel: 0,
          panels: @[
            Panel(
              name: "Assets",
              isWorkingArea: true,
              forceDisplayName: false,
              minWidthPx: 400,
              minHeightPx: 300,
              body: renderAssets()
            )
          ]
        )
      ]
    ),

    Column(
      width: 250,
      rows: @[
        Row(
          height: 100,
          activePanel: 1,
          panels: @[
            Panel(
              name: "New Record",
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: renderNewRecord()
            ),
            Panel(
              name: "Info",
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: renderInfo()
            )
          ]
        )
      ]
    ),
  ]
)

# config.getColumn, config.insertColumn, config.deleteColumn, config.resizeColumn

# config.getRow, config.insertRow, config.deleteRow, config.resizeRow

# config.getPanel, config.insertPanel, config.deletePanel, config.setActivePanel, config.movePanel

karaDock(config)
```

## TODO

* Replace `Config.draggingPanel` by HTML 5.1 `DataTransfer` or by internal state.
* Implement Drag & Drop for panels.
* Automatically collapse/expand rows based on current available `config.height` and sum of `Panel.minHeightPx`.
* Automatically wrap right columns to the left based on current available `config.width` and `Column.width`.

## License
This library is licensed under the MIT license.
Read [LICENSE](https://github.com/pragmagic/karadoc/blob/master/LICENSE) file for details.

Copyright (c) 2017 Pragmagic, Inc.
