import std/[strutils, tables, strtabs, os]
import packages/docutils/[rst, rstgen]

echo """
<!DOCTYPE html>
<head>
	<meta charset="utf-8">
	<style>
		h1,h2{font-family:"trebuchet ms",trebuchet,sans-serif;line-height:1.5}
		body{font-family:tahoma,sans-serif;font-size:10pt;line-height:1.75;}
		h1{font-style:italic;text-align:center;}
		li{margin-bottom:.5em;}
		b{background-color:#ff0;color:#000;}
		code, tt, pre{font-family:courier,monospace;background-color:#eee;color:#000;padding: .15em .25em;border:1px solid #ddd}
        pre{overflow:auto;}
        tt{display:inline-block;}
    </style>
</head>
<body>
"""
echo readfile("ABOUT.rst").rstToHtml(
  {roSupportRawDirective}, modeStyleInsensitive.newStringTable()
)
echo """
</body>
</html>
"""
