Rem
Copyright (c) 2009 Noel R. Cower

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EndRem

SuperStrict

Module Cower.BufferedGLMax2D

Import Brl.Max2D
Import Brl.LinkedList
Import Brl.GLGraphics
Import Cower.RenderBuffer

Public

Type TGLBufferedImageFrame Extends TImageFrame
	Field _name%, _gseq:Int, _texSize:Int, _w:Int, _h:Int, _right:Float, _top:Float
	
	Method New()
		_gseq = GraphicsSeq
	End Method
	
	Method InitWithPixmap:TGLBufferedImageFrame(pixmap:TPixmap, flags:Int)
		_w = pixmap.width
		_h = pixmap.height
		
		glGenTextures(1, Varptr _name)
		TRenderState.SetTexture(_name)
		
		Local magFilter% = GL_NEAREST
		Local minFilter% = GL_NEAREST
		If flags&FILTEREDIMAGE Then
			magFilter = GL_LINEAR
			If flags&MIPMAPPEDIMAGE Then
				minFilter = GL_LINEAR_MIPMAP_LINEAR
			Else
				minFilter = GL_LINEAR
			EndIf
		ElseIf flags&MIPMAPPEDIMAGE Then
			minFilter = GL_NEAREST_MIPMAP_NEAREST
		EndIf
		
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter)
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
		
		Local size%=%1, maxSize% = Max(pixmap.width, pixmap.height)
		While size < maxsize
			size :Shl 1
		Wend
		_texSize = size
		
		_right# = Float(pixmap.width)/Float(size)
		_top# = Float(pixmap.height)/Float(size)
		
		Local format% = GL_RGBA
		Select pixmap.format
			Case PF_A8 ; format = GL_ALPHA8
			Case PF_I8 ; format = GL_LUMINANCE8
			Case PF_RGB888 ; format = GL_RGB
			Case PF_BGR888 ; format = GL_BGR
'			Case PF_RGBA8888 ; format = GL_RGBA 'default
			Case PF_BGRA8888 ; format = GL_BGRA
		End Select
		
		Local level:Int = 0
		Repeat
			glTexImage2D(GL_TEXTURE_2D, level, GL_RGBA8, size, size, 0, format, GL_UNSIGNED_BYTE, Null)
			If size = 1 Then Exit
			level :+ 1
			size :/ 2
		Forever
		
		size = _texSize
		level = 0
		Repeat
			glTexSubImage2D(GL_TEXTURE_2D, level, 0, 0, pixmap.width, pixmap.height, format, GL_UNSIGNED_BYTE, pixmap.pixels)
			Local err%=glGetError();Assert err=GL_NO_ERROR Else err
			If Not (flags&MIPMAPPEDIMAGE) Then Exit
			If size = 1 Then Exit
			level :+ 1
			size :/ 2
			pixmap = ResizePixmap(pixmap, pixmap.width/2 Or 1, pixmap.height/2 Or 1)
		Forever
		
		Return Self
	End Method
	
	Field uv:Float[8]
	Method Draw(x0#, y0#, x1#, y1#, tx#, ty#, sx#, sy#, sw#, sh#)
		Assert _gseq = GraphicsSeq Else "Image no longer exists"
		_activeDriver._buffer.SetTexture(_name)
		_activeDriver._buffer.SetMode(GL_TRIANGLE_STRIP)
		
		Local u0#, u1#, v0#, v1#
		u0 = (sx/Float(_w))*_right
		u1 = ((sx+sw)/Float(_w))*_right
		v0 = (sy/Float(_h))*_top
		v1 = ((sy+sh)/Float(_h))*_top
		
		uv[0]=u0
		uv[1]=v0
		uv[2]=u1
		uv[3]=v0
		uv[4]=u0
		uv[5]=v1
		uv[6]=u1
		uv[7]=v1
		_activeDriver._buffer.AddVerticesEx(4, _activeDriver._rectPoints(x0,y0,x1,y1,tx,ty), uv, _activeDriver._poly_colors)
	End Method
	
	Method Delete()
		If _gseq = GraphicsSeq Then
			glDeleteTextures(1, Varptr _name)
		EndIf
		_name = 0
		_gseq = 0
	End Method
End Type


Private

Global _activeDriver:TBufferedGLMax2DDriver = Null


Public

Type TBufferedGLMax2DDriver Extends TMax2DDriver
	Field _buffer:TRenderBuffer = New TRenderBuffer
	Field _cr@, _cg@, _cb@, _ca@
	
	Field _txx#=1, _txy#=0, _tyx#=0, _tyy#=1
	
	Field _view_x%=0
	Field _view_y%=0
	Field _view_w%=-1
	Field _view_h%=-1
	
	Method Reset()
		glewinit()
		glEnableClientState(GL_VERTEX_ARRAY)
		glEnableClientState(GL_COLOR_ARRAY)
		glEnableClientState(GL_TEXTURE_COORD_ARRAY)
		TRenderState.RestoreState(Null)
		SetResolution(_r_width, _r_height)
	End Method
	
	Method _rectPoints:Float[](x0#, y0#, x1#, y1#, tx#, ty#)
		' Saves on 8 multiplications, which isn't really a big deal, but the code is cleaner for it.
		Local x0xx:Float = x0*_txx
		Local x0yx:Float = x0*_tyx
		Local x1xx:Float = x1*_txx
		Local x1yx:Float = x1*_tyx
		
		Local y0xy:Float = y0*_txy
		Local y0yy:Float = y0*_tyy
		Local y1xy:Float = y1*_txy
		Local y1yy:Float = y1*_tyy
		
		_poly_xyz[0] = x0xx + y0xy + tx
		_poly_xyz[1] = x0yx + y0yy + ty
		_poly_xyz[3] = x1xx + y0xy + tx
		_poly_xyz[4] = x1yx + y0yy + ty
		_poly_xyz[6] = x0xx + y1xy + tx
		_poly_xyz[7] = x0yx + y1yy + ty
		_poly_xyz[9] = x1xx + y1xy + tx
		_poly_xyz[10] = x1yx + y1yy + ty
		
		Return _poly_xyz
	End Method
	
	Method _drawRect(x0#, y0#, x1#, y1#, tx#, ty#)
		_buffer.SetMode(GL_TRIANGLE_STRIP)
		_buffer.AddVerticesEx( 4, ..
			_rectPoints(x0,y0,x1,y1,tx,ty), ..
			Null, ..
			_poly_colors )
	End Method
	
	' TGraphicsDriver
	
	Method GraphicsModes:TGraphicsMode[]()
		Return GLGraphicsDriver().GraphicsModes()
	End Method
	
	Method AttachGraphics:TGraphics(widget%, flags%)
		Local gfx:TGLGraphics = GLGraphicsDriver().AttachGraphics(widget, flags)
		If gfx Then
			Return TMax2DGraphics.Create(gfx, Self)
		EndIf
		Return Null
	End Method
	
	Method CreateGraphics:TGraphics(width%, height%, depth%, hertz%, flags%)
		Local gfx:TGLGraphics = GLGraphicsDriver().CreateGraphics(width, height, depth, hertz, flags)
		If gfx Then
			Return TMax2DGraphics.Create(gfx, Self)
		EndIf
		Return Null
	End Method
	
	Method SetGraphics(g:TGraphics)
		If Not g Then
			TMax2DGraphics.ClearCurrent()
			GLGraphicsDriver().SetGraphics(Null)
			Return
		EndIf
		
		Local m2d:TMax2DGraphics = TMax2DGraphics(g)
		Assert m2d And TGLGraphics(m2d._graphics)
		
		GLGraphicsDriver().SetGraphics(m2d._graphics)
		Reset()
		m2d.MakeCurrent()
	End Method
	
	Method Flip(sync%)
		_buffer.Render()
		GLGraphicsDriver().Flip(sync)
		_buffer.Reset()
		glLoadIdentity()
	End Method
	
	' TMax2DDriver
	
	Method CreateFrameFromPixmap:TImageFrame(pixmap:TPixmap, flags%)
		Return New TGLBufferedImageFrame.InitWithPixmap(pixmap, flags)
	End Method
	
	Method SetBlend(blend%)
		Select blend
			Case MASKBLEND
				_buffer.SetBlendFunc(GL_ONE, GL_ZERO)
				_buffer.SetAlphaFunc(GL_GEQUAL, .5)
			Case SOLIDBLEND
				_buffer.SetBlendFunc(GL_ONE, GL_ZERO)
				_buffer.SetAlphaFunc(GL_ALWAYS, 0)
			Case ALPHABLEND
				_buffer.SetBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
				_buffer.SetAlphaFunc(GL_ALWAYS, 0)
			Case LIGHTBLEND
				_buffer.SetBlendFunc(GL_SRC_ALPHA, GL_ONE)
				_buffer.SetAlphaFunc(GL_ALWAYS, 0)
			Case SHADEBLEND
				_buffer.SetBlendFunc(GL_DST_COLOR, GL_ZERO)
				_buffer.SetAlphaFunc(GL_ALWAYS, 0)
			Default
				RuntimeError "Invalid blendmode specified: "+blend
		End Select
	End Method
	
	Method SetAlpha(alpha#)
		_ca=Int(alpha*255)&$FF
		For Local i:Int = 0 Until _poly_colors.Length Step 4
			_poly_colors[i+3] = _ca
		Next
	End Method
	
	Method SetColor(r%, g%, b%)
		_cr=r&$FF
		_cg=g&$FF
		_cb=b&$FF
		For Local i:Int = 0 Until _poly_colors.Length Step 4
			_poly_colors[i] = _cr
			_poly_colors[i+1] = _cg
			_poly_colors[i+2] = _cb
		Next
	End Method
	
	Method SetClsColor(r%, g%, b%)
		glClearColor(r/255#, g/255#, b/255#, 1.0)
	End Method
	
	Method SetViewport(x%, y%, w%, h%)
	End Method
	
	Method SetTransform(xx#, xy#, yx#, yy#)
		_txx = xx
		_txy = xy
		_tyx = yx
		_tyy = yy
	End Method
	
	Method SetLineWidth(width#)
		_buffer.SetLineWidth(width)
	End Method
	
	Method Cls()
		glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT)
	End Method
	
	Method Plot(x#, y#)
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_POINTS)
		_poly_xyz[0] = x
		_poly_xyz[1] = y
		_poly_xyz[2] = 0
		_buffer.AddVerticesEx(1, _poly_xyz, Null, _poly_colors)
	End Method
	
	Method DrawLine(x0#, y0#, x1#, y1#, tx#, ty#)
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_LINES)
		_poly_xyz[0] = x0*_txx+y0*_txy+tx+.5
		_poly_xyz[1] = x0*_tyx+y0*_tyy-1+ty+.5
		_poly_xyz[2] = 0
		_poly_xyz[0] = x1*_txx+y1*_txy+tx+.5
		_poly_xyz[1] = x1*_tyx+y1*_tyy-1+ty+.5
		_poly_xyz[2] = 0
		_buffer.AddVerticesEx(2, _poly_xyz, Null, _poly_colors)
	End Method
	
	Method DrawRect(x0#, y0#, x1#, y1#, tx#, ty#)
		_buffer.SetTexture(0)
		_drawRect(x0,y0,x1,y1,tx,ty)
	End Method
	
	Method DrawOval(x0#, y0#, x1#, y1#, tx#, ty#)
		RuntimeError("Not implemented")
	End Method
	
	Field _poly_xyz#[36]
	Field _poly_colors:Byte[36]
	Method DrawPoly(xy#[], handlex#, handley#, originx#, originy#)
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_POLYGON)
		
		If _poly_xyz.Length/3 < xy.Length/2 Then _poly_xyz = New Float[Min(xy.Length/2,12)*3]
		For Local i:Int = 0 Until xy.Length Step 2
			Local ti:Int = (i/2)*3
			Local x#,y#
			x = xy[i]
			y = xy[i+1]
			
			x :+ handlex
			y :+ handley
			x = (x * _txx) + (y * _txy) + originx
			y = (x * _tyx) + (y * _tyy) + originy
			
			_poly_xyz[ti] = x
			_poly_xyz[ti+1] = y
			_poly_xyz[ti+2] = 0
		Next
		_buffer.AddVerticesEx(xy.Length, _poly_xyz, Null, _poly_colors)
	End Method
		
	Method DrawPixmap(pixmap:TPixmap, x%, y%)
		RuntimeError("Not implemented")
	End Method
	
	Method GrabPixmap:TPixmap(x%, y%, width%, height%)
		_buffer.Render()
		_buffer.Reset()
		
		' Do something here...
		RuntimeError("Not implemented")
		
		Return Null
	End Method
	
	Field _r_width#=640, _r_height#=480 ' dummy values
	Method SetResolution(width#, height#)
		_r_width = width
		_r_height = height
		
		glMatrixMode(GL_PROJECTION)
		glLoadIdentity()
		glOrtho(0, width, height, 0, -32, 32)
		glMatrixMode(GL_MODELVIEW)
		glLoadIdentity()
	End Method
	
	Method ToString$()
		Return "OpenGL (Buffered)"
	End Method
	
	Method RenderBuffer:TRenderBuffer()
		Return _buffer
	End Method
End Type

' That's a mouthful
Function BufferedGLMax2DDriver:TBufferedGLMax2DDriver()
	' Borrowing this idea from the original GLMax2D
	Global _done:Int = False
	If Not _done Then
		_done = True
		If Not GLGraphicsDriver() Then
			Return Null
		EndIf
		_activeDriver = New TBufferedGLMax2DDriver
	EndIf
	Return _activeDriver
End Function
BufferedGLMax2DDriver()
