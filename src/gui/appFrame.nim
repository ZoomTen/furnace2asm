import wNim/[
    wApp, wFrame, wMacros, wImage, wButton,
    wRegion, wPaintDC, wMemoryDC,
    wBitmap, wBrush, wPanel, wStaticText, wFont, wTextCtrl,
    wFileDialog, wIcon, wCheckBox, wMessageDialog
]
import std/[strutils, strformat]
import ../convert
import ./aboutDialog
import ./helpDialog

const
    bkgBitmap = staticRead("images/window.png")
    icoOk = staticRead("images/ok.ico")
    icoOpen = staticRead("images/open.ico")
    icoHelp = staticRead("images/help.ico")
    icoInfo = staticRead("images/info.ico")
    icoExit = staticRead("images/exit.ico")

type
    wMyAppFrame* = ref object of wFrame
        imgBackground: wImage
        dcContext: wMemoryDC
        canvas: wPanel
        # iInfoText: wStaticText

        lblSourceFurHeader, lblDestAsmHeader: wStaticText
        lblOpenedFurIndicator, lblOpenedAsmIndicator: wStaticText
        btnOpenFur, btnOpenAsm, btnConvert: wButton

        btnHelp, btnAbout, btnExit: wButton

        chkUseOldStyle: wCheckBox

        wOpenedFur, wOpenedAsm: string
    
    AreaRange = object
        x, y, w, h: int

func withinRange(range: AreaRange, x, y: int): bool {.inline.} =
    (x >= range.x) and (x < (range.x + range.w)) and 
    (y >= range.y) and (y < (range.y + range.h))

wClass(wMyAppFrame of wFrame):
    # fwd declarations
    proc updateDisplay(self: wMyAppFrame)
    proc initControls(self: wMyAppFrame) {.inline.}
    proc attachControls(self: wMyAppFrame) {.inline.}

    proc init(self: wMyAppFrame) =
        self.imgBackground = Image(bkgBitmap)

        # setup frame info
        wFrame(self).init(
            title="Furnace2ASM",
            size=self.imgBackground.size,
            style=0
        )
        self.clearWindowStyle(wCaption)
        self.shape = Region(self.imgBackground)
        
        # setup display context for background drawing
        self.dcContext = MemoryDC()
        self.dcContext.selectObject(
            Bitmap(self.size)
        )
        self.dcContext.setBackground(wBlackBrush)
        self.updateDisplay()

        # canvas for absolute positioning of controls
        self.canvas = self.Panel(
            (0, 0),
            self.size
        )

        var
            savedPos: wPoint = (-1, -1)
            posIsSaved: bool = false

        # emulate dragging the window frame
        # setDraggable doesn't work for weird things like this
        self.canvas.wEvent_MouseMove do (e: wEvent):
            if e.leftDown():
                let
                    rPos = getMousePos(e)
                    sPos = getMouseScreenPos(e)
                if rPos.y < 228: # limit of top bar
                    if not posIsSaved:
                        savedPos = rPos
                        posIsSaved = true
                    self.position=(
                        sPos.x - savedPos.x,
                        sPos.y - savedPos.y
                    )
            else:
                posIsSaved = false

        # do bitmap button regions
        self.canvas.wEvent_LeftDown do (e: wEvent):
            let pos = getMousePos(e)

            # minimize buttton
            if AreaRange(
                x:519, y:96,
                w:23, h:23
            ).withinRange(pos[0], pos[1]):
                self.minimize()
            
            # close button
            if AreaRange(
                x:554, y:96,
                w:23, h:23
            ).withinRange(pos[0], pos[1]):
                self.close()
        
        # paint the background
        self.canvas.wEvent_Paint do ():
            var dc = self.canvas.PaintDC()
            let size = dc.size
            dc.blit(
                source=self.dcContext,
                width=size.width,
                height=size.height
            )
            dc.delete
        
        self.canvas.setFont(
            Font(faceName="tahoma", pointSize=10.0, weight=wFontWeightNormal)
        )
        self.initControls()
        self.attachControls()
    
    proc openFur(self: wMyAppFrame) =
        let dlg = self.FileDialog(
                wildcard="Furnace project (*.fur)|*.fur",
                style=wFdOpen or wFdFileMustExist
            )
        if dlg.showModal() == wIdOk:
            self.wOpenedFur = dlg.path
            self.lblOpenedFurIndicator.setLabel self.wOpenedFur
    
    proc openAsm(self: wMyAppFrame) =
        let dlg = self.FileDialog(
            wildcard="Assembly source (*.asm)|*.asm",
            style=wFdSave or wFdOverwritePrompt
        )
        if dlg.showModal() == wIdOk:
            var path = dlg.path()
            if not path.endsWith(".asm"):
                path &= ".asm"
            self.wOpenedAsm = path
            self.lblOpenedAsmIndicator.setLabel self.wOpenedAsm
    
    proc doConvert(self: wMyAppFrame) =
        if self.wOpenedFur.strip() == "":
            discard self.MessageDialog(
                message="Pick a project file first...",
                caption="No input file",
                style=wIconErr
            ).showModal()
        elif self.wOpenedAsm.strip() == "":
            discard self.MessageDialog(
                message="Where do you wanna save it?",
                caption="No output file",
                style=wIconErr
            ).showModal()
        else:
            try:
                writeFile(
                    self.wOpenedAsm,
                    convertFile(
                        self.wOpenedFur, self.chkUseOldStyle.isChecked()
                    ).replace("\n","\r\n")
                )
                discard self.MessageDialog(
                    message="Successfully converted! You may want to edit the resulting file.",
                    caption="Success",
                    style=wIconAsterisk
                ).showModal()
            except CatchableError as e:
                discard self.MessageDialog(
                    message=e.msg,
                    caption=fmt"{e.name}",
                    style=wIconErr
                ).showModal()
    
    proc attachControls(self: wMyAppFrame) =
        self.btnOpenFur.wEvent_Button do ():
            self.openFur()
        
        self.btnOpenAsm.wEvent_Button do ():
            self.openAsm()
        
        self.lblOpenedFurIndicator.wEvent_LeftDown do ():
            self.openFur()
        
        self.lblOpenedAsmIndicator.wEvent_LeftDown do ():
            self.openAsm()
        
        self.btnExit.wEvent_Button do ():
            self.close()
        
        self.btnAbout.wEvent_Button do ():
            AboutDialog(self)
        
        self.btnHelp.wEvent_Button do ():
            HelpDialog(self)
        
        self.btnConvert.wEvent_Button do ():
            self.doConvert()
    
    proc initControls(self: wMyAppFrame) =
        block addHeaders:
            self.lblSourceFurHeader = self.canvas.StaticText(
                label="1. Open your module file",
                pos=(160, 260), size=(400, 20)
            )
            self.lblSourceFurHeader.setBackgroundColor(-1)
            self.lblSourceFurHeader.setForegroundColor(wBlack)
            self.lblSourceFurHeader.setFont(
                Font(faceName="tahoma", pointSize=11.0, weight=wFontWeightBold)
            )
            self.lblDestAsmHeader = self.canvas.StaticText(
                label="2. Pick where you want the ASM file",
                pos=(160, 320), size=(400, 20)
            )
            self.lblDestAsmHeader.setBackgroundColor(-1)
            self.lblDestAsmHeader.setForegroundColor(wBlack)
            self.lblDestAsmHeader.setFont(
                Font(faceName="tahoma", pointSize=11.0, weight=wFontWeightBold)
            )
        block addTextBoxes:
            self.lblOpenedFurIndicator = self.canvas.StaticText(
                label="*.fur",
                pos=(240, 285), size=(320, 25),
                style=wBorderSunken or wAlignLeftNoWordWrap
            )
            self.lblOpenedAsmIndicator = self.canvas.StaticText(
                label="*.asm",
                pos=(240, 345), size=(320, 25),
                style=wBorderSunken or wAlignLeftNoWordWrap
            )
        block addButtons:
            self.btnOpenFur = self.canvas.Button(
                label="&Open",
                pos=(160, 285), size=(75, 25)
            )
            self.btnOpenAsm = self.canvas.Button(
                label="&Save",
                pos=(160, 345), size=(75, 25)
            )
            self.btnConvert = self.canvas.Button(
                label="Convert :)",
                pos=(480, 385), size=(80, 30)
            )

            self.btnOpenFur.setIcon Icon(icoOpen)
            self.btnOpenAsm.setIcon Icon(icoOk)

            self.btnHelp = self.canvas.Button(
                label="Help",
                pos=(35, 260), size=(100, 40)
            )
            self.btnAbout = self.canvas.Button(
                label="About",
                pos=(35, 320), size=(100, 40)
            )
            self.btnExit = self.canvas.Button(
                label="Exit",
                pos=(35, 380), size=(100, 40)
            )

            self.btnHelp.setIcon Icon(icoHelp)
            self.btnAbout.setIcon Icon(icoInfo)
            self.btnExit.setBitmap Bitmap(icoExit)

            self.btnHelp.setBitmap4Margins (8,8,0,8)
            self.btnAbout.setBitmap4Margins (8,8,0,8)
            self.btnExit.setBitmap4Margins (8,8,0,8)
        block addMisc:
            self.chkUseOldStyle = self.canvas.CheckBox(
                label="Use old pret macros",
                pos=(160, 385), size=(305, 24)
            )
            self.chkUseOldStyle.setBackgroundColor wWhite
    
    proc updateDisplay(self: wMyAppFrame) =
        self.dcContext.clear()
        self.dcContext.drawImage(self.imgBackground)
        self.refresh(eraseBackground=true)

# so the main module can see it
export MyAppFrame
