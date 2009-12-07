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

Module Cower.GLMax2D

Import Brl.Max2D
Import Brl.LinkedList
Import Brl.GLGraphics
Import Pub.OpenGL
Import Pub.Glew

Private

Function FloatsDiffer:Int(a:Float, b:Float) NoDebug
	Const FLOAT_EPSILON:Float = 5.96e-08
	Return Abs(a-b) > FLOAT_EPSILON
End Function

Type TRenderIndices
	Field indexFrom:Int = 0
	Field indices:Int = 0
	Field numIndices:Int = 0
End Type

Type TRenderState
	Field textureName:Int = 0	' may be zero
	
	Field renderMode:Int = GL_POLYGON' GL_POLYGON, etc.
	
	Field blendSource:Int = GL_ONE
	Field blendDest:Int = GL_ZERO
	
	Field alphaFunc:Int = GL_ALWAYS
	Field alphaRef:Float = 0 'GLclampf
	
	Field lineWidth:Float = 1
	
	Method Bind()
		If _current = Self Then
			Return
		EndIf
		
		SetTexture(textureName)
		
		If Not _current Or blendDest <> _current.blendDest Or blendSource <> _current.blendSource Then
			If blendDest = GL_ONE And blendDest = GL_ZERO And _blendEnabled Then
				glDisable(GL_BLEND)
				_blendEnabled = False
			Else
				If Not _blendEnabled Then
					glEnable(GL_BLEND)
					_blendEnabled = True
				EndIf
				glBlendFunc(blendSource, blendDest)
			EndIf
		EndIf
		
		If Not _current Or alphaFunc <> _current.alphaFunc Or FloatsDiffer(alphaRef, _current.alphaRef) Then
			If alphaFunc = GL_ALWAYS And _alphaTestEnabled Then
				glDisable(GL_ALPHA_TEST)
				_alphaTestEnabled = False
			Else
				If Not _alphaTestEnabled Then
					glEnable(GL_ALPHA_TEST)
					_alphaTestEnabled = True
				EndIf
				glAlphaFunc(alphaFunc, alphaRef)
			EndIf
		EndIf
		
		If renderMode = GL_LINES And FloatsDiffer(lineWidth, _current.lineWidth) Then
			glLineWidth(lineWidth)
		EndIf
		
		_current = Clone()
	End Method
	
	Method Restore()
		RestoreState(Self)
	End Method
	
	Method Clone:TRenderState()
		Local c:TRenderState = New TRenderState
		MemCopy(Varptr c.textureName, Varptr textureName, SizeOf(TRenderState))
		Return c
	End Method
	
	Global _current:TRenderState
	Global _texture2DEnabled:Int = False
	Global _activeTexture:Int = 0
	Global _atexSeq:Int = 0
	Global _blendEnabled:Int = False
	Global _alphaTestEnabled:Int = False
	
	Function SetTexture(tex%)
		If tex = _activeTexture And _atexSeq = GraphicsSeq Then
			Return
		EndIf
		
		If tex Then
			If Not _texture2DEnabled Or _atexSeq <> GraphicsSeq Then
				glEnable(GL_TEXTURE_2D)
				_texture2DEnabled = True
			EndIf
			glBindTexture(GL_TEXTURE_2D, tex)
		ElseIf _texture2DEnabled Or _atexSeq = GraphicsSeq Then
			glDisable(GL_TEXTURE_2D)
			_texture2DEnabled = False
		EndIf
		_atexSeq = GraphicsSeq
		_activeTexture = tex
	End Function
	
	Function RestoreState(state:TRenderState=Null)
		Global _ed(cap%)[] = [glDisable, glEnable] ' this is evil
		
		If state = Null Then
			If _current Then
				state = _current
			Else
				state = New TRenderState
			EndIf
		EndIf
		_current = Null
		
		state.Bind()
		
		' this is also evil
		_ed[_alphaTestEnabled] GL_ALPHA_TEST
		_ed[_blendEnabled] GL_BLEND
		_ed[_texture2DEnabled And _activeTexture] GL_TEXTURE_2D
		If _atexSeq = GraphicsSeq And _texture2DEnabled And _activeTexture Then
			glBindTexture(GL_TEXTURE_2D, _activeTexture)
		Else
			_activeTexture = 0
		EndIf
	End Function
End Type

Type TRenderBuffer
	Const RENDER_BUFFER_SIZE_BYTES:Int = 131072 '128kb
 
	Field _vertbuffer:TBank, _vertstream:TBankStream
	Field _texcoordbuffer:TBank, _texcoordstream:TBankStream
	Field _colorbuffer:TBank, _colorstream:TBankStream
	Field _index:Int = 0, _sets%=0
	Field _arrindices:Int[], _arrcounts:Int[]
	Field _lock%=0
	
	Field _renderIndexStack:TList
	Field _indexTop:TRenderIndices
	
	Field _renderStateStack:TList
	Field _stateTop:TRenderState
 
	Method New()
		_vertbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_vertstream = TBankStream.Create(_vertbuffer)
		
		_texcoordbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_texcoordstream = TBankStream.Create(_texcoordbuffer)
		
		_colorbuffer = TBank.Create(RENDER_BUFFER_SIZE_BYTES)
		_colorstream = TBankStream.Create(_colorbuffer)
		
		_arrindices = New Int[512]
		_arrcounts = New Int[512]
		
		_stateTop = New TRenderState
		_renderStateStack = New TList
		_renderStateStack.AddLast(_stateTop)
		
		_indexTop = New TRenderIndices
		_renderIndexStack = New TList
		_renderIndexStack.AddLast(_indexTop)
	End Method
	
	' Add a new state/index 
	Method _newState()
		If _indexTop.indices Then
			_indexTop = New TRenderIndices
			_indexTop.indexFrom = _sets
			_renderIndexStack.AddLast(_indexTop)
			
			_stateTop = _stateTop.Clone()
			_renderStateStack.AddLast(_stateTop)
		EndIf
	End Method
	
	Method SetTexture(tex:Int)
		If _stateTop.textureName <> tex Then
			_newState()
			_stateTop.textureName = tex
		EndIf
	End Method
	
	Method SetMode(mode:Int)
		If _stateTop.renderMode <> mode Then
			_newState()
			_stateTop.renderMode = mode
		EndIf
	End Method
	
	Method SetBlendFunc(sfac:Int, dfac:Int)
		If _stateTop.blendSource <> sfac Or _stateTop.blendDest <> dfac Then
			_newState()
			_stateTop.blendSource = sfac
			_stateTop.blendDest = dfac
		EndIf
	End Method
	
	Method SetAlphaFunc(func:Int, ref:Float)
		If _stateTop.alphaFunc <> func Or FloatsDiffer(_stateTop.alphaRef, ref) Then
			_newState()
			_stateTop.alphaFunc = func
			_stateTop.alphaRef = ref
		EndIf
	End Method
	
	Method SetLineWidth(width#)
		If FloatsDiffer(_stateTop.lineWidth, width) Then
			_newState()
			_stateTop.lineWidth = width
		EndIf
	End Method
 
	Method AddVerticesEx(points:Float[], texcoords:Float[], colors:Byte[])
		Assert _lock=0 Else "Buffers are locked for rendering"
		Assert colors.Length/4 = points.Length/3 And points.Length/3 = texcoords.Length/2 And ..
			(points.Length Mod 3 = 0 And texcoords.Length Mod 2 = 0 And colors.Length Mod 4 = 0) ..
			Else "Incorrect buffer sizes - buffers must describe the same number of vertices"
 
		If _sets >= _arrindices.Length Then
			_arrindices = _arrindices[.. _arrindices.Length*2]
			_arrcounts = _arrcounts[.. _arrcounts.Length*2]
		EndIf
 
		Local numIndices:Int = points.Length/3
		
		_arrindices[_sets] = _index
		_arrcounts[_sets] = numIndices
 
		_texcoordstream.WriteBytes(texcoords, texcoords.Length*4)
		_vertstream.WriteBytes(points, points.Length*4)
		_colorstream.WriteBytes(colors, colors.Length)
		
		_sets :+ 1
		_indexTop.indices :+ 1
		
		_index :+ numIndices
		_indexTop.numIndices :+ numIndices
	End Method
	
	Method LockBuffers()
		If _lock = 0 Then
			glVertexPointer(3, GL_FLOAT, 0, _vertbuffer.Lock())
			glColorPointer(4, GL_UNSIGNED_BYTE, 0, _colorbuffer.Lock())
			glTexCoordPointer(2, GL_FLOAT, 0, _texcoordbuffer.Lock())
		EndIf
		_lock :+ 1
	End Method
 
	Method UnlockBuffers()
		Assert _lock > 0 Else "Unmatched unlock for buffers"
		_lock :- 1
		If _lock = 0 Then
			glVertexPointer(4, GL_FLOAT, 0, Null)
			glColorPointer(4, GL_FLOAT, 0, Null)
			glTexCoordPointer(4, GL_FLOAT, 0, Null)
			_vertbuffer.Unlock()
			_colorbuffer.Unlock()
			_texcoordbuffer.Unlock()
		EndIf
	End Method
 
	Method Render()
		LockBuffers ' because we don't want to be robbed
		
		Local indexPointer%Ptr, countPointer%Ptr
		Local indexEnum:TListEnum, stateEnum:TListEnum
		
		' there's probably a better way to do this.  Like having another type that contains both the state and indices.  Or something.
		indexEnum = _renderIndexStack.ObjectEnumerator()
		stateEnum = _renderStateStack.ObjectEnumerator()
		While indexEnum.HasNext() And stateEnum.HasNext()
			Local state:TRenderState = TRenderState(stateEnum.NextObject())
			Local index:TRenderIndices = TRenderIndices(indexEnum.NextObject())
			
			If index.indices = 0 Then
				Continue
			EndIf
			
			state.Bind()
			
			If glMultiDrawArrays Then
				If 1 < index.indices Then
					glMultiDrawArrays(state.renderMode, Varptr _arrindices[index.indexFrom], Varptr _arrcounts[index.indexFrom], index.indices)
				Else
					glDrawArrays(state.renderMode, _arrindices[index.indexFrom], _arrcounts[index.indexFrom])
				EndIf
			Else
				For Local i:Int = index.indexFrom Until index.indices
					glDrawArrays(state.renderMode, _arrindices[i], _arrcounts[i])
				Next
			EndIf
		Wend
		
		UnlockBuffers ' but sometimes we think we're safe
	End Method
 
	Method Reset()
		' make like nothing happened and equip a wig of charisma
		Assert _lock = 0 Else "Buffers are locked for rendering"
		_vertstream.Seek(0)
		_texcoordstream.Seek(0)
		_colorstream.Seek(0)
		_index = 0
		_sets = 0
		
		_stateTop = _stateTop.Clone()
		_renderStateStack.Clear()
		_renderStateStack.AddLast(_stateTop)
		
		_indexTop = New TRenderIndices
		_renderIndexStack.Clear()
		_renderIndexStack.AddLast(_indexTop)
	End Method
End Type

Public

Type TGLBufferedImageFrame Extends TImageFrame
	Field _name%, _gseq:Int, _texSize:Int, _w:Int, _h:Int
	Field _uv:Float[8]
	
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
		
		Local left# = Float(pixmap.width)/Float(size)
		Local bottom# = Float(pixmap.height)/Float(size)
		
		_uv[2] = left
		_uv[5] = bottom
		_uv[6] = left
		_uv[7] = bottom
		
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
	
	Method Draw(x0#, y0#, x1#, y1#, tx#, ty#)
		Assert _gseq = GraphicsSeq Else "Image no longer exists"
		_activeDriver._buffer.SetTexture(_name)
		_activeDriver._buffer.SetMode(GL_TRIANGLE_STRIP)
		_activeDriver._buffer.AddVerticesEx(_activeDriver._rectPoints(x0,y0,x1,y1,tx,ty), _uv, _activeDriver._rectColor)
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
		
		Return [x0xx + y0xy + tx, x0yx + y0yy + ty, 0#, ..
				x1xx + y0xy + tx, x1yx + y0yy + ty, 0#, ..
				x0xx + y1xy + tx, x0yx + y1yy + ty, 0#, ..
				x1xx + y1xy + tx, x1yx + y1yy + ty, 0# ]
	End Method
	
	Method _drawRect(x0#, y0#, x1#, y1#, tx#, ty#)
		Global _rectUV:Float[8]
		_buffer.SetMode(GL_TRIANGLE_STRIP)
		_buffer.AddVerticesEx( ..
			_rectPoints(x0,y0,x1,y1,tx,ty), ..
			_rectUV, ..
			_rectColor )
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
		_rectColor[3]=_ca;_rectColor[7]=_ca;_rectColor[11]=_ca;_rectColor[15]=_ca;
		_lineColor[3]=_ca;_lineColor[7]=_ca;_plotColor[3]=_ca
	End Method
	
	Method SetColor(r%, g%, b%)
		_cr=r&$FF
		_cg=g&$FF
		_cb=b&$FF
		_rectColor[0]=_cr;_rectColor[4]=_cr;_rectColor[8]=_cr;_rectColor[12]=_cr;
		_lineColor[0]=_cr;_lineColor[4]=_cr;_plotColor[0]=_cr
		_rectColor[1]=_cg;_rectColor[5]=_cg;_rectColor[9]=_cg;_rectColor[13]=_cg;
		_lineColor[1]=_cg;_lineColor[5]=_cg;_plotColor[1]=_cg
		_rectColor[2]=_cb;_rectColor[6]=_cb;_rectColor[10]=_cb;_rectColor[14]=_cb;
		_lineColor[2]=_cb;_lineColor[6]=_cb;_plotColor[2]=_cb
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
	
	Field _plotColor:Byte[]=[255:Byte,255:Byte,255:Byte,255:Byte]
	Method Plot(x#, y#)
		Global _plotUV:Float[2]'garbage
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_POINTS)
		_buffer.AddVerticesEx([x, y, 0#], _plotUV, _plotColor)
	End Method
	
	Field _lineColor:Byte[]=[255:Byte,255:Byte,255:Byte,255:Byte,255:Byte,255:Byte,255:Byte,255:Byte]
	Method DrawLine(x0#, y0#, x1#, y1#, tx#, ty#)
		Global _lineUV:Float[4]'garbage
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_LINES)
		_buffer.AddVerticesEx(..
			[	x0*_txx+y0*_txy+tx+.5, x0*_tyx+y0*_tyy-1+ty+.5, 0#, ..
				x1*_txx+y1*_txy+tx+.5, x1*_tyx+y1*_tyy-1+ty+.5, 0#], ..
				_lineUV, _lineColor)
	End Method
	
	Field _rectColor:Byte[]=[255:Byte,255:Byte,255:Byte,255:Byte, 255:Byte,255:Byte,255:Byte,255:Byte,..
							255:Byte,255:Byte,255:Byte,255:Byte, 255:Byte,255:Byte,255:Byte,255:Byte]
	Method DrawRect(x0#, y0#, x1#, y1#, tx#, ty#)
		_buffer.SetTexture(0)
		_drawRect(x0,y0,x1,y1,tx,ty)
	End Method
	
	Method DrawOval(x0#, y0#, x1#, y1#, tx#, ty#)
		RuntimeError("Not implemented")
	End Method
	
	Method DrawPoly(xy#[], handlex#, handley#, originx#, originy#)
		_buffer.SetTexture(0)
		_buffer.SetMode(GL_POLYGON)
		
		Local xyz#[xy.Length/2*3]
		Local colors:Byte[xy.Length*2]
		For Local i:Int = 0 Until xy.Length Step 2
			Local ti:Int = (i/2)*3
			Local x#,y#
			x = xy[i]
			y = xy[i+1]
			
			x :+ handlex
			y :+ handley
			x = (x * _txx) + (y * _txy) + originx
			y = (x * _tyx) + (y * _tyy) + originy
			
			xyz[ti] = x
			xyz[ti+1] = y
			
			ti = i*2
			colors[ti] = _cr
			colors[ti+1] = _cg
			colors[ti+2] = _cb
			colors[ti+3] = _ca
		Next
		_buffer.AddVerticesEx(xyz, xy, colors)
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
'		RuntimeError("Not implemented")
	End Method
	
	Method ToString$()
		Return "OpenGL (Buffered)"
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
