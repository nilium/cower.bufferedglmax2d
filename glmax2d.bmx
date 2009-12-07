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

' TODO: driver
