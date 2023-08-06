import wNim/[
    wApp, wFrame, wMacros, wPanel, wWebView, wButton
]

type
    wHelpDialog* = ref object of wFrame
        canvas: wPanel
        btnOk: wButton
        txHelp: wWebView

const
    htHelp = staticRead("images/helpText.html")

wClass(wHelpDialog of wFrame):
    proc init(self: wHelpDialog, owner: wWindow) =
        wFrame(self).init(
            title="Furnace2Asm help",
            owner=owner,
            style=wCaption or wDefaultDialogStyle,
            size=(400, 420)
        )
        
        self.canvas = self.Panel()

        self.autolayout """
        H:|self.canvas|
        V:|self.canvas|
        """

        self.btnOk = self.canvas.Button(
            label="Got it!"
        )

        self.txHelp = self.canvas.WebView()
        self.txHelp.setHtml(htHelp)

        let
            ok = self.btnOk
            help = self.txHelp
        
        self.canvas.autolayout """
        spacing: 10
        V:|-[help]-[ok(28)]-|
        H:|-[help]-|
        H:|-[ok]-|
        """
        
        self.btnOk.wEvent_Button do ():
            self.close()
        
        self.show()

export HelpDialog