import ../res/resources
import wNim/[wApp, wFrame]
import appFrame

import winim/lean

when isMainModule:
  let
    app = App(wSystemDpiAware)
    app_frm = MyAppFrame()

  when defined(fancyEffects):
    AnimateWindow(app_frm.mHwnd, 500, AW_ACTIVATE or AW_BLEND)
  else:
    app_frm.show()

  app.mainLoop()
