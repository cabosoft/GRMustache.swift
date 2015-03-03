// The MIT License
//
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import Foundation

// "It's all boxes all the way down."
//
// Mustache templates don't eat raw values: they eat boxed values.
//
// To box something, you use the Box() function. It comes in several
// variants so that nearly anything can be boxed and feed templates.
//
// This file is organized in five sections with many examples. You can use the
// Playground included in `Mustache.xcworkspace` to run those examples.
//
//
// - MustacheBox
//
//   Describes the MustacheBox type, and the most generic Box() function
//
//
// - MustacheBoxable and the Boxing of Swift scalar types
//
//   The MustacheBoxable protocol makes any Swift type able to be boxed with
//   the Box(MustacheBoxable?) function.
//
//   Learn how the Swift types Bool, Int, UInt, Double, and String are rendered.
//
//
// - Boxing of Swift collections and dictionaries
//
//   There is one Box() function for collections, and another one for
//   dictionaries.
//
//
// - ObjCMustacheBoxable and the Boxing of Objective-C objects
//
//   There is a Box() function for Objective-C objects.
//
//   Learn how NSObject, NSNull, NSString, NSNumber, NSArray, NSDictionary and
//   NSSet are rendered.
//
//
// - Boxing of Core Mustache functions
//
//   The "core Mustache functions" are raw filters, Mustache lambdas, etc. Those
//   can be boxed as well so that you can feed templates with filters,
//   Mustache lambdas, and more.


// =============================================================================
// MARK: - MustacheBox

/**
MustacheBox wraps values that feed your templates.

This type has no public initializer. To produce boxes, you use one variant of
the Box() function, or BoxAnyObject().

:see: Box()
:see: BoxAnyObject()
*/
public struct MustacheBox {
    
    // -------------------------------------------------------------------------
    // MARK: - The boxed value
    
    /**
    The boxed value.
    */
    public let value: Any?
    
    /**
    The only empty boxes are Box() and Box(NSNull())
    */
    public let isEmpty: Bool
    
    /**
    The boolean value of the box.
    
    It tells whether the Box should trigger or prevent the rendering of regular
    {{#section}}...{{/}} and inverted {{^section}}...{{/}}.
    */
    public let boolValue: Bool
    
    /**
    If the boxed value is a Swift numerical value, a Bool, or an NSNumber,
    returns this value as an Int.
    */
    public var intValue: Int? {
        return converter?.intValue?()
    }
    
    /**
    If the boxed value is a Swift numerical value, a Bool, or an NSNumber,
    returns this value as a UInt.
    */
    public var uintValue: UInt? {
        return converter?.uintValue?()
    }
    
    /**
    If the boxed value is a Swift numerical value, a Bool, or an NSNumber,
    returns this value as a Double.
    */
    public var doubleValue: Double? {
        return converter?.doubleValue?()
    }
    
    /**
    If boxed value can be iterated (Swift collection, NSArray, NSSet, etc.),
    returns a [MustacheBox].
    */
    public var arrayValue: [MustacheBox]? {
        return converter?.arrayValue?()
    }
    
    /**
    If boxed value is a dictionary (Swift dictionary, NSDictionary, etc.),
    returns a [String: MustacheBox] dictionary.
    */
    public var dictionaryValue: [String: MustacheBox]? {
        return converter?.dictionaryValue?()
    }
    
    
    // -------------------------------------------------------------------------
    // MARK: - Rendering a Box
    
    /**
    TODO
    */
    public let render: RenderFunction
    
    
    // -------------------------------------------------------------------------
    // MARK - Key extraction
    
    /**
    Extract a key out of a box.
    
    ::
    
      let box = Box("Arthur")
      box["length"].intValue!    // 6
    */
    public subscript (key: String) -> MustacheBox {
        return mustacheSubscript?(key: key) ?? Box()
    }
    
    
    // -------------------------------------------------------------------------
    // MARK: - Internal
    
    let mustacheSubscript: SubscriptFunction?
    let filter: FilterFunction?
    let willRender: WillRenderFunction?
    let didRender: DidRenderFunction?
    let converter: Converter?
    
    init(
        boolValue: Bool? = nil,
        value: Any? = nil,
        converter: Converter? = nil,
        mustacheSubscript: SubscriptFunction? = nil,
        filter: FilterFunction? = nil,
        render: RenderFunction? = nil,
        willRender: WillRenderFunction? = nil,
        didRender: DidRenderFunction? = nil)
    {
        let empty = (value == nil) && (mustacheSubscript == nil) && (render == nil) && (filter == nil) && (willRender == nil) && (didRender == nil)
        self.isEmpty = empty
        self.value = value
        self.converter = converter
        self.boolValue = boolValue ?? !empty
        self.mustacheSubscript = mustacheSubscript
        self.filter = filter
        self.willRender = willRender
        self.didRender = didRender
        if let render = render {
            self.render = render
        } else {
            // Set self.render twice in order to avoid the compiler error:
            // "variable 'self.render' captured by a closure before being initialized"
            self.render = { (_, _) in return nil }
            self.render = { (info: RenderingInfo, error: NSErrorPointer) in
                switch info.tag.type {
                case .Variable:
                    // {{ box }}
                    if let value = value {
                        return Rendering("\(value)")
                    } else {
                        return Rendering("")
                    }
                case .Section:
                    // {{# box }}...{{/ box }}
                    let context = info.context.extendedContext(self)
                    return info.tag.renderInnerContent(context, error: error)
                }
            }
        }
    }
    
    // Converter wraps all the conversion closures that help MustacheBox expose
    // its raw value (typed Any) as useful types.
    //
    // Without those conversions, it would be very difficult for the library
    // user to write code that processes, for example, a boxed number.
    struct Converter {
        let intValue: (() -> Int?)?
        let uintValue: (() -> UInt?)?
        let doubleValue: (() -> Double?)?
        let arrayValue: (() -> [MustacheBox]?)?
        let dictionaryValue: (() -> [String: MustacheBox]?)?
        
        init(
            intValue: (() -> Int?)? = nil,
            uintValue: (() -> UInt?)? = nil,
            doubleValue: (() -> Double?)? = nil,
            arrayValue: (() -> [MustacheBox]?)? = nil,
            dictionaryValue: (() -> [String: MustacheBox]?)? = nil)
        {
            self.intValue = intValue
            self.uintValue = uintValue
            self.doubleValue = doubleValue
            self.arrayValue = arrayValue
            self.dictionaryValue = dictionaryValue
        }
    }

    // Hackish helper function which helps us boxing NSArray and NSNull.
    func boxWithValue(value: Any?) -> MustacheBox {
        return MustacheBox(
            boolValue: self.boolValue,
            value: value,
            converter: self.converter,
            mustacheSubscript: self.mustacheSubscript,
            filter: self.filter,
            render: self.render,
            willRender: self.willRender,
            didRender: self.didRender)
    }
}

extension MustacheBox : DebugPrintable {
    
    public var debugDescription: String {
        if let value = value {
            return "MustacheBox(\(value))"  // remove "Optional" from the output
        } else {
            return "MustacheBox(nil)"
        }
    }
}


/**
This function is the most low-level function that lets you build MustacheBox
for feeding templates.

It is suited for building somewhat "advanced" boxes. There are other simpler
versions of the Box() function that may well better suit your need; you should
check them.

It can take up to seven parameters, all optional, that define how the box
interacts with the Mustache engine:

:param: boolValue         An optional boolean value for the Box.
:param: value             An optional boxed value
:param: mustacheSubscript An optional SubscriptFunction
:param: filter            An optional FilterFunction
:param: render            An optional RenderFunction
:param: willRender        An optional WillRenderFunction
:param: didRender         An optional DidRenderFunction


To illustrate the usage of all those parameters, let's look at how the {{f(a)}}
tag is rendered.

First the `a` and `f` expressions are evaluated. The Mustache engine looks in
the context stack for boxes whose *mustacheSubscript* return non-empty boxes for
the keys "a" and "f". Let's call them aBox and fBox.

Then the *filter* of the fBox is evaluated with aBox as an argument. It is
likely that the result depends on the *value* of the aBox: it is the resultBox.

Then the Mustache engine is ready to render resultBox. It looks in the context
stack for boses whose *willRender* function is defined. Those willRender
functions have the opportunity to process the resultBox, and eventually provide
the box that will be actually rendered: the renderedBox.

The renderedBox has a *render* function: it is evaluated by the Mustache engine
which appends its result to the final rendering.

Finally the Mustache engine looks in the context stack for boxes whose
*didRender* function is defined, and call them.


The optional boolValue parameter tells whether the Box should trigger or prevent
the rendering of regular {{#section}}...{{/}} and inverted {{^section}}...{{/}}.
The default value is true, unless the function is called without argument to
build the empty box: Box().

::

  // Render "true", "false"
  let template = Template(string:"{{#.}}true{{/.}}{{^.}}false{{/.}}")!
  template.render(Box(boolValue: true))!
  template.render(Box(boolValue: false))!


The optional value parameter gives the boxed value. You should generally provide
one, although the value is only used when evaluating filters, and not all
templates use filters. The default value is nil.


The optional mustacheSubscript parameter is a SubscriptFunction that lets the
Mustache engine extract keys out of the box. For example, the {{a}} tag would
call the SubscriptFunction with "a" as an argument, and render the returned box.
The default value is nil, which means that no key can be extracted.

:see: SubscriptFunction for a full discussion of this type.

::

  // Renders "key:a"
  let template = Template(string:"{{a}}")!
  let box = Box(mustacheSubscript: { (key: String) in
      return Box("key:\(key)")
  })
  template.render(box)!


The optional filter parameter is a FilterFunction that lets the Mustache engine
evaluate filtered expression that involve the box. The default value is nil,
which means that the box can not be used as a filter.

:see: FilterFunction for a full discussion of this type.

::

  // Renders "100"
  let template = Template(string:"{{square(x)}}")!
  let box = Box(filter: Filter { (int: Int, _) in
      return Box(int * int)
  })
  template.render(Box(["square": box, "x": Box(10)]))!


The optional render parameter is a RenderFunction that is evaluated when the Box
gets rendered. The default value is nil, which makes the box perform default
Mustache rendering of values. RenderFunctions are functions that let you
implement, for example, Mustache lambdas.

:see: RenderFunction for a full discussion of this type.

::

  // Renders "foo"
  let template = Template(string:"{{.}}")!
  let box = Box(render: { (info: RenderingInfo, _) in
      return Rendering("foo")
  })
  template.render(box)!


The optional willRender and didRender parameters are a WillRenderFunction and
DidRenderFunction that are evaluated for all tags as long as the box is in the
context stack.

:see: WillRenderFunction and DidRenderFunction for a full discussion of those
types.

::

  // Renders "baz baz"
  let template = Template(string:"{{#.}}{{foo}} {{bar}}{{/.}}")!
  let box = Box(willRender: { (tag: Tag, box: MustacheBox) in
      return Box("baz")
  })
  template.render(box)!


By mixing all those parameters, you can tune the behavior of a box. Example:

::

  // Nothing special here:

  class Person {
      let firstName: String
      let lastName: String
      
      init(firstName: String, lastName: String) {
          self.firstName = firstName
          self.lastName = lastName
      }
  }
  

  // Have Person conform to MustacheBoxable so that we can box people, and
  // render them:

  extension Person : MustacheBoxable {

      // MustacheBoxable protocol requires objects to implement this property
      // and return a MustacheBox:

      var mustacheBox: MustacheBox {

          // A person is a multi-facetted object:
          return Box(
              // It has a value:
              value: self,
              
              // It lets Mustache extracts values by name:
              mustacheSubscript: self.mustacheSubscript,
              
              // It performs custom rendering:
              render: self.render)
      }
      

      // The SubscriptFunction that lets the Mustache engine extract values by
      // name. Let's expose the `firstName`, `lastName` and `fullName`:

      func mustacheSubscript(key: String) -> MustacheBox {
          switch key {
          case "firstName": return Box(firstName)
          case "lastName": return Box(lastName)
          case "fullName": return Box("\(firstName) \(lastName)")
          default: return Box()
          }
      }

      
      // A custom RenderFunction that avoids default Mustache rendering:

      func render(info: RenderingInfo, error: NSErrorPointer) -> Rendering? {
          switch info.tag.type {
          case .Variable:
              // Custom rendering of {{ person }} variable tags:
              return Rendering("\(firstName) \(lastName)")
          case .Section:
              // Regular rendering of {{# person }}...{{/}} section tags:
              // Extend the context with self, and render the inner content of
              // the section tag:
              let context = info.context.extendedContext(Box(self))
              return info.tag.renderInnerContent(context, error: error)
          }
      }
  }
  
  // Renders "The person is Errol Flynn"
  let person = Person(firstName: "Errol", lastName: "Flynn")
  let template = Template(string: "{{# person }}The person is {{.}}{{/ person }}")!
  template.render(Box(["person": person]))!
*/
public func Box(
    boolValue: Bool? = nil,
    value: Any? = nil,
    mustacheSubscript: SubscriptFunction? = nil,
    filter: FilterFunction? = nil,
    render: RenderFunction? = nil,
    willRender: WillRenderFunction? = nil,
    didRender: DidRenderFunction? = nil) -> MustacheBox
{
    return MustacheBox(
        boolValue: boolValue,
        value: value,
        mustacheSubscript: mustacheSubscript,
        filter: filter,
        render: render,
        willRender: willRender,
        didRender: didRender)
}


// =============================================================================
// MARK: - MustacheBoxable and the Boxing of Swift scalar types

/**
The MustacheBoxable protocol lets your custom Swift types feed Mustache
templates.

NB: this protocol is not tailored for Objective-C classes. See the
documentation of NSObject.mustacheBox for more information.
*/
public protocol MustacheBoxable {
    
    /**
    Returns a MustacheBox.
    
    This method is invoked when a value of your conforming class is boxed with
    the Box() function. You can not return Box(self) since this would trigger
    an infinite loop. Instead you build a Box that explicitly describes how your
    conforming type interacts with the Mustache engine.
    
    For example:
    
    ::
    
      struct Person {
          let firstName: String
          let lastName: String
      }
    
      extension Person : MustacheBoxable {
          var mustacheBox: MustacheBox {
              // Return a Box that wraps our user, and exposes the `firstName`,
              // `lastName` and `fullName` to templates:
              return Box(value: self) { (key: String) in
                  switch key {
                  case "firstName":
                      return Box(self.firstName)
                  case "lastName":
                      return Box(self.lastName)
                  case "fullName":
                      return Box("\(self.firstName) \(self.lastName)")
                  default:
                      return Box()
                  }
              }
          }
      }
    
      // Renders "Tom Selleck"
      let template = Template(string: "{{person.fullName}}")!
      let person = Person(firstName: "Tom", lastName: "Selleck")
      template.render(Box(["person": Box(person)]))!
    
    There are several variants of the Box() function. Check their documentation.
    */
    var mustacheBox: MustacheBox { get }
}

/**
See the documentation of the MustacheBoxable protocol.
*/
public func Box(boxable: MustacheBoxable?) -> MustacheBox {
    if let boxable = boxable {
        return boxable.mustacheBox
    } else {
        return Box()
    }
}

// This protocol conformance is not only a matter of consistency. It is also a
// convenience for the library implementation: it makes an array [MustacheBox]
// boxable via the Box<CollectionType where C.Generator.Element: MustacheBoxable>()
// function.
extension MustacheBox : MustacheBoxable {
    
    /**
    MustacheBox is obviously boxable: its mustacheBox property return self.
    */
    public var mustacheBox: MustacheBox {
        return self
    }
}

extension Bool : MustacheBoxable {
    
    /**
    Let Bool feed Mustache templates.
    
    GRMustache makes sure Bool and NSNumber wrapping bools have the same
    behavior: whatever the actual type of boxed bools, your templates render
    the same.
    
    In particular, bools have all the behaviors of numbers:
    
    ::
    
      // Renders "0 is falsey. 1 is truthy."
      let template = Template(string: "{{#bools}}{{.}} is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["bools": [false, true]]
      template.render(Box(data))!
    
    Whenever you want to extract a Bool out of a box, beware that some casts
    of the raw boxed value will fail. You may prefer the MustacheBox property
    boolValue which never fails.
    
    ::
    
      let boxedNSNumber = Box(NSNumber(bool: false))
      let boxedInt = Box(0)
      let boxedBool = Box(false)
      
      boxedNSNumber.value as NSNumber // 0
      // boxedNSNumber.value as Bool  // Error
      boxedInt.value as NSNumber      // 0
      // boxedInt.value as Bool       // Error
      boxedBool.value as NSNumber     // 0
      boxedBool.value as Bool         // false
      
      boxedNSNumber.boolValue         // false
      boxedInt.boolValue              // false
      boxedBool.boolValue             // false
    */
    public var mustacheBox: MustacheBox {
        return MustacheBox(
            value: self,
            converter: MustacheBox.Converter(
                intValue: { self ? 1 : 0 },         // Behave like [NSNumber numberWithBool:]
                uintValue: { self ? 1 : 0 },        // Behave like [NSNumber numberWithBool:]
                doubleValue: { self ? 1.0 : 0.0 }), // Behave like [NSNumber numberWithBool:]
            boolValue: self,
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                switch info.tag.type {
                case .Variable:
                    // {{ bool }}
                    return Rendering("\(self ? 1 : 0)") // Behave like [NSNumber numberWithBool:]
                case .Section:
                    if info.enumerationItem {
                        // {{# bools }}...{{/ bools }}
                        return info.tag.renderInnerContent(info.context.extendedContext(Box(self)), error: error)
                    } else {
                        // {{# bool }}...{{/ bool }}
                        //
                        // Bools do not enter the context stack when used in a
                        // boolean section.
                        //
                        // This behavior must not change:
                        // https://github.com/groue/GRMustache/issues/83
                        return info.tag.renderInnerContent(info.context, error: error)
                    }
                }
        })
    }
}

extension Int : MustacheBoxable {
    
    /**
    Let Int feed Mustache templates.
    
    Int can be used as a boolean. 0 is the only falsey value:
    
    ::
    
      // Renders "0 is falsey. 1 is truthy."
      let template = Template(string: "{{#numbers}}{{.}} is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["numbers": [0, 1]]
      template.render(Box(data))!
    
    GRMustache makes sure Int and NSNumber wrapping integers have the same
    behavior: whatever the actual type of boxed numbers, your templates render
    the same.
    
    Whenever you want to extract a Int out of a box, beware that some casts
    of the raw boxed value will fail. You may prefer the MustacheBox property
    intValue which never fails as long as the boxed value is numeric.
    
    ::
    
      let boxedNSNumber = Box(NSNumber(integer: 1))
      let boxedDouble = Box(1.0)
      let boxedInt = Box(1)
      
      boxedNSNumber.value as NSNumber // 1
      boxedNSNumber.value as Int      // 1
      boxedDouble.value as NSNumber   // 1.0
      // boxedDouble.value as Int     // Error
      boxedInt.value as NSNumber      // 1
      boxedInt.value as Int           // 1
      
      boxedNSNumber.intValue          // 1
      boxedDouble.intValue            // 1
      boxedInt.intValue               // 1
    */
    public var mustacheBox: MustacheBox {
        return MustacheBox(
            value: self,
            converter: MustacheBox.Converter(
                intValue: { self },
                uintValue: { UInt(self) },
                doubleValue: { Double(self) }),
            boolValue: (self != 0),
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                switch info.tag.type {
                case .Variable:
                    // {{ int }}
                    return Rendering("\(self)")
                case .Section:
                    if info.enumerationItem {
                        // {{# ints }}...{{/ ints }}
                        return info.tag.renderInnerContent(info.context.extendedContext(Box(self)), error: error)
                    } else {
                        // {{# int }}...{{/ int }}
                        //
                        // Ints do not enter the context stack when used in a
                        // boolean section.
                        //
                        // This behavior must not change:
                        // https://github.com/groue/GRMustache/issues/83
                        return info.tag.renderInnerContent(info.context, error: error)
                    }
                }
        })
    }
}

extension UInt : MustacheBoxable {
    
    /**
    Let UInt feed Mustache templates.
    
    UInt can be used as a boolean. 0 is the only falsey value:
    
    ::
    
      // Renders "0 is falsey. 1 is truthy."
      let template = Template(string: "{{#numbers}}{{.}} is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["numbers": [0 as UInt, 1 as UInt]]
      template.render(Box(data))!
    
    GRMustache makes sure UInt and NSNumber wrapping uints have the same
    behavior: whatever the actual type of boxed numbers, your templates render
    the same.
    
    Whenever you want to extract a UInt out of a box, beware that some casts
    of the raw boxed value will fail. You may prefer the MustacheBox property
    uintValue which never fails as long as the boxed value is numeric.
    
    ::
    
      let boxedNSNumber = Box(NSNumber(unsignedInteger: 1))
      let boxedUInt = Box(1 as UInt)
      let boxedInt = Box(1)
      
      boxedNSNumber.value as NSNumber // 1
      // boxedNSNumber.value as UInt  // Error
      boxedUInt.value as NSNumber     // 1
      boxedUInt.value as UInt         // 1
      boxedInt.value as NSNumber      // 1
      // boxedInt.value as UInt       // Error
      
      boxedNSNumber.uintValue         // 1
      boxedUInt.uintValue             // 1
      boxedInt.uintValue              // 1
    */
    public var mustacheBox: MustacheBox {
        return MustacheBox(
            value: self,
            converter: MustacheBox.Converter(
                intValue: { Int(self) },
                uintValue: { self },
                doubleValue: { Double(self) }),
            boolValue: (self != 0),
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                switch info.tag.type {
                case .Variable:
                    // {{ uint }}
                    return Rendering("\(self)")
                case .Section:
                    if info.enumerationItem {
                        // {{# uints }}...{{/ uints }}
                        return info.tag.renderInnerContent(info.context.extendedContext(Box(self)), error: error)
                    } else {
                        // {{# uint }}...{{/ uint }}
                        //
                        // Uints do not enter the context stack when used in a
                        // boolean section.
                        //
                        // This behavior must not change:
                        // https://github.com/groue/GRMustache/issues/83
                        return info.tag.renderInnerContent(info.context, error: error)
                    }
                }
        })
    }
}

extension Double : MustacheBoxable {
    
    /**
    Let Double feed Mustache templates.
    
    Double can be used as a boolean. 0.0 is the only falsey value:
    
    ::
    
      // Renders "0.0 is falsey. 1.0 is truthy."
      let template = Template(string: "{{#numbers}}{{.}} is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["numbers": [0.0, 1.0]]
      template.render(Box(data))!
    
    GRMustache makes sure Double and NSNumber wrapping doubles have the same
    behavior: whatever the actual type of boxed numbers, your templates render
    the same.
    
    Whenever you want to extract a Double out of a box, beware that some casts
    of the raw boxed value will fail. You may prefer the MustacheBox property
    doubleValue which never fails as long as the boxed value is numeric.
    
    ::
    
      let boxedNSNumber = Box(NSNumber(double: 1.0))
      let boxedDouble = Box(1.0)
      let boxedInt = Box(1)
      
      boxedNSNumber.value as NSNumber // 1.0
      boxedNSNumber.value as Double   // 1.0
      boxedDouble.value as NSNumber   // 1.0
      boxedDouble.value as Double     // 1.0
      boxedInt.value as NSNumber      // 1
      // boxedInt.value as Double     // Error
      
      boxedNSNumber.doubleValue       // 1.0
      boxedDouble.doubleValue         // 1.0
      boxedInt.doubleValue            // 1.0
    */
    public var mustacheBox: MustacheBox {
        return MustacheBox(
            value: self,
            converter: MustacheBox.Converter(
                intValue: { Int(self) },
                uintValue: { UInt(self) },
                doubleValue: { self }),
            boolValue: (self != 0.0),
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                switch info.tag.type {
                case .Variable:
                    // {{ double }}
                    return Rendering("\(self)")
                case .Section:
                    if info.enumerationItem {
                        // {{# doubles }}...{{/ doubles }}
                        return info.tag.renderInnerContent(info.context.extendedContext(Box(self)), error: error)
                    } else {
                        // {{# double }}...{{/ double }}
                        //
                        // Doubles do not enter the context stack when used in a
                        // boolean section.
                        //
                        // This behavior must not change:
                        // https://github.com/groue/GRMustache/issues/83
                        return info.tag.renderInnerContent(info.context, error: error)
                    }
                }
        })
    }
}

extension String : MustacheBoxable {
    
    /**
    Let String feed Mustache templates.
    
    Strings are rendered HTML-escaped by {{ double-mustache }} tags, and raw
    by {{{ triple-mustache }}} tags:
    
    ::
    
      // Renders "Escaped: Arthur &amp; Barbara, Non-escaped: Arthur & Barbara"
      var template = Template(string: "Escaped: {{string}}, Non-escaped: {{{string}}}")!
      template.render(Box(["string": "Arthur & Barbara"]))!
    
    Empty strings are falsey:
    
    ::
    
      // Renders "`` is falsey. `yeah` is truthy."
      let template = Template(string: "{{#strings}}`{{.}}` is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["strings": ["", "yeah"]]
      template.render(Box(data))!
    
    GRMustache makes sure String and NSString have the same behavior: whatever
    the actual type of boxed strings, your templates render the same.
    
    Whenever you want to extract a string out of a box, cast the boxed value to
    String or NSString:
    
    ::
    
      let box = Box("foo")
      box.value as String     // "foo"
      box.value as NSString   // "foo"
    
    If the box does not contain a String, this cast would fail. If you want to
    process the rendering of a value ("123" for 123), consider looking at the
    documentation of:
    
    - func Filter(filter: (Rendering, NSErrorPointer) -> Rendering?) -> FilterFunction
    - RenderFunction
    
    For example, the `twice` filter below is able to render any value twice (not
    only strings):
    
    ::
    
      let twice = Filter { (rendering: Rendering, _) in
          return Rendering(rendering.string + rendering.string)
      }
      
      var template = Template(string: "{{twice(x)}}")!
      template.registerInBaseContext("twice", Box(twice))
      
      // Renders "123123"
      template.render(Box(["x": 123]))!
    
    The `uppercase` RenderFunction below is able to render the uppercase version
    of a section (regardless of the types of the values rendered inside):
    
    ::
    
      let uppercase: RenderFunction = { (info: RenderingInfo, _) in
          let rendering = info.tag.renderInnerContent(info.context)!
          return Rendering(rendering.string.uppercaseString)
      }
      
      var template = Template(string: "{{#uppercase}}{{name}} is {{age}}.{{/uppercase}}")!
      template.registerInBaseContext("uppercase", Box(uppercase))
      
      // Renders "ARTHUR IS 36."
      template.render(Box(["name": "Arthur", "age": 36]))!
    */
    public var mustacheBox: MustacheBox {
        return MustacheBox(
            value: self,
            boolValue: (countElements(self) > 0),
            mustacheSubscript: { (key: String) in
                switch key {
                case "length":
                    return Box(countElements(self))
                default:
                    return Box()
                }
            })
    }
}


// =============================================================================
// MARK: - Boxing of Swift collections and dictionaries


// This function is a private helper for collection types CollectionType and
// NSSet. Collections render as the concatenation of the rendering of their
// items.
//
// There are two tricks when rendering collections:
//
// One, items can render as Text or HTML, and our collection should render with
// the same type. It is an error to mix content types.
//
// Two, we have to tell items that they are rendered as an enumeration item.
// This allows collections to avoid enumerating their items when they are part
// of another collections:
//
// ::
//
//   {{# arrays }}  // Each array renders as an enumeration item, and has itself enter the context stack.
//     {{#.}}       // Each array renders "normally", and enumerates its items
//       ...
//     {{/.}}
//   {{/ arrays }}
private func renderCollection<C: CollectionType where C.Generator.Element: MustacheBoxable, C.Index: BidirectionalIndexType, C.Index.Distance == Int>(collection: C, var info: RenderingInfo, error: NSErrorPointer) -> Rendering? {
    
    // Prepare the rendering. We don't known the contentType yet: it depends on items
    var buffer = ""
    var contentType: ContentType? = nil
    
    // Tell items they are rendered as an enumeration item.
    //
    // Some values don't render the same whenever they render as an enumeration
    // item, or alone: {{# values }}...{{/ values }} vs.
    // {{# value }}...{{/ value }}.
    //
    // This is the case of Int, UInt, Double, Bool: they enter the context
    // stack when used in an iteration, and do not enter the context stack when
    // used as a boolean.
    //
    // This is also the case of collections: they enter the context stack when
    // used as an item of a collection, and enumerate their items when used as
    // a collection.

    info.enumerationItem = true
    
    for item in collection {
        if let boxRendering = Box(item).render(info: info, error: error) {
            if contentType == nil
            {
                // First item: now we know our contentType
                contentType = boxRendering.contentType
                buffer += boxRendering.string
            }
            else if contentType == boxRendering.contentType
            {
                // Consistent content type: keep on buffering.
                buffer += boxRendering.string
            }
            else
            {
                // Inconsistent content type: this is an error. How are we
                // supposed to mix Text and HTML?
                if error != nil {
                    error.memory = NSError(domain: GRMustacheErrorDomain, code: GRMustacheErrorCodeRenderingError, userInfo: [NSLocalizedDescriptionKey: "Content type mismatch"])
                }
                return nil
            }
        } else {
            return nil
        }
    }
    
    if let contentType = contentType {
        // {{ collection }}
        // {{# collection }}...{{/ collection }}
        //
        // We know our contentType, hence the collection is not empty and
        // we render our buffer.
        return Rendering(buffer, contentType)
    } else {
        // {{ collection }}
        //
        // We don't know our contentType, hence the collection is empty.
        //
        // Now this code is executed. This means that the collection is
        // rendered, despite its emptiness.
        //
        // We are not rendering a regular {{# section }} tag, because empty
        // collections have a false boolValue, and RenderingEngine would prevent
        // us to render.
        //
        // We are not rendering an inverted {{^ section }} tag, because
        // RenderingEngine takes care of the rendering of inverted sections.
        //
        // So we are rendering a {{ variable }} tag. Return its empty rendering:
        return info.tag.renderInnerContent(info.context, error: error)
    }
}

// We don't provide any boxing function for `SequenceType`, because this type
// makes no requirement on conforming types regarding whether they will be
// destructively "consumed" by iteration (as stated by documentation).
//
// Now we need to consume a sequence several times:
//
// - for converting it to an array for the arrayValue property.
// - for consuming the first element to know if the sequence is empty or not.
// - for rendering it.
//
// So we only provide a boxing function for `CollectionType` which ensures
// non-destructive iteration.

/**
A function that wraps a collection of MustacheBoxable.

::

  let box = Box([1,2,3])
*/
public func Box<C: CollectionType where C.Generator.Element: MustacheBoxable, C.Index: BidirectionalIndexType, C.Index.Distance == Int>(collection: C?) -> MustacheBox {
    if let collection = collection {
        let count = distance(collection.startIndex, collection.endIndex)    // C.Index.Distance == Int
        return MustacheBox(
            boolValue: (count > 0),
            value: collection,
            converter: MustacheBox.Converter(arrayValue: { map(collection) { Box($0) } }),
            mustacheSubscript: { (key: String) in
                switch key {
                case "count":
                    // Support for both Objective-C and Swift arrays.
                    return Box(count)
                    
                case "firstObject", "first":
                    // Support for both Objective-C and Swift arrays.
                    if count > 0 {
                        return Box(collection[collection.startIndex])
                    } else {
                        return Box()
                    }
                    
                case "lastObject", "last":
                    // Support for both Objective-C and Swift arrays.
                    if count > 0 {
                        return Box(collection[collection.endIndex.predecessor()])   // C.Index: BidirectionalIndexType
                    } else {
                        return Box()
                    }
                    
                default:
                    return Box()
                }
            },
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                if info.enumerationItem {
                    // {{# collections }}...{{/ collections }}
                    return info.tag.renderInnerContent(info.context.extendedContext(Box(collection)), error: error)
                } else {
                    // {{ collection }}
                    // {{# collection }}...{{/ collection }}
                    // {{^ collection }}...{{/ collection }}
                    return renderCollection(collection, info, error)
                }
        })
    } else {
        return Box()
    }
}


/**
A function that wraps a dictionary of MustacheBoxable.

::

  let box = Box(["firstName": "Freddy", "lastName": "Mercury"])
*/
public func Box<T: MustacheBoxable>(dictionary: [String: T]?) -> MustacheBox {
    if let dictionary = dictionary {
        
        return MustacheBox(
            value: dictionary,
            converter: MustacheBox.Converter(
                dictionaryValue: {
                    var boxDictionary: [String: MustacheBox] = [:]
                    for (key, item) in dictionary {
                        boxDictionary[key] = Box(item)
                    }
                    return boxDictionary
                }),
            mustacheSubscript: { (key: String) in
                return Box(dictionary[key])
            })
    } else {
        return Box()
    }
}


// =============================================================================
// MARK: - ObjCMustacheBoxable and the Boxing of Objective-C objects

/**
Keys of Objective-C objects are extracted with the objectForKeyedSubscript:
method if it is available, or with valueForKey:, as long as the key is "safe".
Safe keys are, by default, property getters and NSManagedObject attributes. The
GRMustacheSafeKeyAccess protocol lets a class specify a custom list of safe keys
that are available through valueForKey:.
*/
@objc public protocol GRMustacheSafeKeyAccess {
    
    /**
    Returns the keys that GRMustache can access using the `valueForKey:` method.
    */
    class func safeMustacheKeys() -> NSSet
}

/**
The ObjCMustacheBoxable protocol lets Objective-C classes interact with the
Mustache engine.

The NSObject class already conforms to this protocol: you will override the
mustacheBox if you need to provide custom rendering behavior. For an example,
look at the NSFormatter.swift source file.

See the Swift-targetted MustacheBoxable protocol for more information.
*/
@objc public protocol ObjCMustacheBoxable {
    
    /**
    Returns a MustacheBox wrapped in a ObjCMustacheBox (this wrapping is
    required by the constraints of the Swift type system).
    
    This method is invoked when a value of your conforming class is boxed with
    the Box() function. You can not return Box(self) since this would trigger
    an infinite loop. Instead you build a Box that explicitly describes how your
    conforming type interacts with the Mustache engine.
    
    See the Swift-targetted MustacheBoxable protocol for more information.
    */
    var mustacheBox: ObjCMustacheBox { get }
}

/**
An NSObject subclass whose sole pupose is to wrap a MustacheBox.

See the documentation of the ObjCMustacheBoxable protocol.
*/
public class ObjCMustacheBox: NSObject {
    let box: MustacheBox
    init(_ box: MustacheBox) {
        self.box = box
    }
}

/**
See the documentation of the ObjCMustacheBoxable protocol.
*/
public func Box(boxable: ObjCMustacheBoxable?) -> MustacheBox {
    if let boxable = boxable {
        return boxable.mustacheBox.box
    } else {
        return Box()
    }
}

/**
Due to constraints in the Swift language, there is no Box(AnyObject) function.

Instead, you use the BoxAnyObject() function:

::

  let set = NSSet(object: "Mario")
  let box = BoxAnyObject(set.anyObject())
  box.value as String  // "Mario"

Important caveat: this function can only box Objective-C objects and Objective-C
briged values such as Strings.

::

  class Person {
      let name: String
      init(name: String) {
          self.name = name
      }
  }

  let person = Person(name: "Charlie Chaplin")
  let set = NSSet(object: person)

  // In the log:
  // Mustache.BoxAnyObject(): value `__lldb_expr_1123.Person` does not conform to the ObjCMustacheBoxable protocol, and is discarded.
  let box = BoxAnyObject(set.anyObject())

  // nil :-(
  box.value

*/
public func BoxAnyObject(object: AnyObject?) -> MustacheBox {
    if let object: AnyObject = object {
        if let boxable = object as? ObjCMustacheBoxable {
            return Box(boxable)
        } else {
            // This code path will only run if object is not a NSObject
            // instance, since NSObject conforms to ObjCMustacheBoxable.
            //
            // This may mean that the class of object is NSProxy or any other
            // Objective-C class that does not derive from NSObject.
            //
            // This may also mean that object is an instance of a pure Swift
            // class.
            //
            // Objective-C objects and containers can contain pure Swift
            // instances. For example, given the following array:
            //
            //     class C: MustacheBoxable { ... }
            //     var array = NSMutableArray()
            //     array.addObject(C())
            //
            // GRMustache *can not* known that the array contains a valid
            // boxable value, because NSArray exposes its contents as AnyObject,
            // and AnyObject can not be tested for MustacheBoxable conformance:
            //
            // https://developer.apple.com/library/prerelease/ios/documentation/Swift/Conceptual/Swift_Programming_Language/Protocols.html#//apple_ref/doc/uid/TP40014097-CH25-XID_363
            // > you need to mark your protocols with the @objc attribute if you want to be able to check for protocol conformance.
            //
            // So GRMustache, when given an AnyObject, generally assumes that it
            // is an Objective-C value, even when it is wrong, and ends up here.
            //
            // As a conclusion: let's apologize.
            //
            // TODO: document caveat with something like:
            //
            // If GRMustache.BoxAnyObject was called from your own code, check
            // the type of the value you provide. If not, it is likely that an
            // Objective-C collection like NSArray, NSDictionary, NSSet or any
            // other Objective-C object contains a value that is not an
            // Objective-C object. GRMustache does not support such mixing of
            // Objective-C and Swift values.
            NSLog("Mustache.BoxAnyObject(): value `\(object)` does not conform to the ObjCMustacheBoxable protocol, and is discarded.")
            return Box()
        }
    } else {
        return Box()
    }
}

extension NSObject : ObjCMustacheBoxable {
    
    /**
    Let any NSObject feed Mustache templates.
    
    GRMustache ships with a few specific classes that provide their own
    rendering behavior: NSFormatter, NSNull, NSNumber, NSString and NSSet.
    
    Your own subclass of NSObject can also override the mustacheBox method so
    that it provides its own rendering behavior.
    
    NSObject's default implementation handles three general cases:
    
    - NSDictionary and dictionary-like objects
    - NSArray and array-like objects (NSOrderedSet for example)
    - other objects
    
    An objet is treated as a dictionary if it conforms to NSFastEnumeration and
    responds to the objectForKeyedSubscript: selector.
    
    ::
    
      let template = Template(string: "{{name}} is {{age}}.")!
    
      // Renders "Arthur is 36."
      let dictionary = ["name": "Arthur", "age": 36] as NSDictionary
      template.render(Box(dictionary))!
    
    
    An objet is treated as an array if it conforms to NSFastEnumeration and
    does not respond to the objectForKeyedSubscript:.
    
    ::
    
      let template = Template(string: "{{#voyels}}{{.}}{{/voyels}}")!
    
      // Renders "AEIOU"
      let data = ["voyels": ["A", "E", "I", "O", "U"] as NSArray]
      template.render(Box(data))!

    Other objects fall in the general case. Their keys are extracted with the
    objectForKeyedSubscript: method if it is available, or with valueForKey:, as
    long as the key is "safe". Safe keys are, by default, property getters and
    NSManagedObject attributes. The GRMustacheSafeKeyAccess protocol lets a
    class specify a custom list of safe keys that are available through
    valueForKey:.
    
    ::
    
      class Person: NSObject {
          let name: String
          let age: UInt
          
          init(name: String, age: UInt) {
              self.name = name
              self.age = age
          }
      }
      
      let template = Template(string: "{{name}} is {{age}}.")!
      
      // Renders "Arthur is 36."
      let person = Person(name: "Arthur", age: 36)
      template.render(Box(person))!
    */
    public var mustacheBox: ObjCMustacheBox {
        if let enumerable = self as? NSFastEnumeration
        {
            // Enumerable
            
            if respondsToSelector("objectForKeyedSubscript:")
            {
                // Dictionary-like enumerable
                
                return ObjCMustacheBox(MustacheBox(
                    value: self,
                    converter: MustacheBox.Converter(
                        dictionaryValue: {
                            var boxDictionary: [String: MustacheBox] = [:]
                            for key in GeneratorSequence(NSFastGenerator(enumerable)) {
                                if let key = key as? String {
                                    let item = (self as AnyObject)[key] // Cast to AnyObject so that we can access subscript notation.
                                    boxDictionary[key] = BoxAnyObject(item)
                                }
                            }
                            return boxDictionary
                        }),
                    mustacheSubscript: { (key: String) in
                        let item = (self as AnyObject)[key] // Cast to AnyObject so that we can access subscript notation.
                        return BoxAnyObject(item)
                    }))
            }
            else
            {
                // Array-like enumerable
                
                let array = map(GeneratorSequence(NSFastGenerator(enumerable))) { BoxAnyObject($0) }
                let box = Box(array).boxWithValue(self)
                return ObjCMustacheBox(box)
            }
        }
        else
        {
            // Generic NSObject
            
            return ObjCMustacheBox(MustacheBox(
                value: self,
                mustacheSubscript: { (key: String) in
                    if self.respondsToSelector("objectForKeyedSubscript:")
                    {
                        // Use objectForKeyedSubscript: first (see https://github.com/groue/GRMustache/issues/66:)
                        return BoxAnyObject((self as AnyObject)[key]) // Cast to AnyObject so that we can access subscript notation.
                    }
                    else if GRMustacheKeyAccess.isSafeMustacheKey(key, forObject: self)
                    {
                        // Use valueForKey: for safe keys
                        return BoxAnyObject(self.valueForKey(key))
                    }
                    else
                    {
                        // Missing key
                        return Box()
                    }
                }))
        }
    }
}

extension NSNull : ObjCMustacheBoxable {
    
    /**
    Let NSNull feed Mustache templates.
    
    NSNull doesn't render anything:
    
    ::
    
      // Renders "null:"
      let template = Template(string: "null:{{null}}")!
      let data = ["null": NSNull()]
      template.render(Box(data))!
    
    NSNull is a falsey value:
    
    ::
    
      // Renders "null is falsey."
      let template = Template(string: "null is {{#null}}truthy{{^}}falsey{{/}}.")!
      let data = ["null": NSNull()]
      template.render(Box(data))!
    
    A Box wrapping NSNull is empty:
    
    ::
    
      let box = Box(NSNull())
      let value = box.value as NSNull   // NSNull
      let isEmpty = box.isEmpty         // true
    */
    public override var mustacheBox: ObjCMustacheBox {
        return ObjCMustacheBox(MustacheBox().boxWithValue(self))
    }
}

extension NSNumber : ObjCMustacheBoxable {
    
    /**
    Let NSNumber feed Mustache templates.
    
    NSNumber whose boolValue is false are falsey:
    
    ::
    
      // Renders "0 is falsey. 1 is truthy."
      let template = Template(string: "{{#numbers}}{{.}} is {{#.}}truthy{{^}}falsey{{/}}.{{/}}")!
      let data = ["numbers": [NSNumber(int: 0), NSNumber(int: 1)]]
      template.render(Box(data))!
    
    GRMustache makes sure NSNumber and Swift types Int, UInt, and Double have the
    same behavior: whatever the actual type of boxed numbers, your templates render
    the same.
    
    Whenever you want to extract a numeric value out of a box, beware that some
    casts of the raw boxed value will fail. You may prefer the MustacheBox
    properties intValue, uintValue and doubleValue which never fail as long
    as the boxed value is numeric.
    
    ::
    
      let box1 = Box(NSNumber(int: 1))
      let box2 = Box(1)
    
      box1.value as NSNumber  // 1
      box1.value as Int       // 1
      //box1.value as UInt    // Error
      //box1.value as Double  // Error
      box2.value as NSNumber  // 1
      box2.value as Int       // 1
      //box2.value as UInt    // Error
      //box2.value as Double  // Error
      
      box1.intValue           // 1
      box1.uintValue          // 1
      box1.doubleValue        // 1.0
      box2.intValue           // 1
      box2.uintValue          // 1
      box2.doubleValue        // 1.0
    */
    public override var mustacheBox: ObjCMustacheBox {
        let objCType = String.fromCString(self.objCType)!
        switch objCType {
        case "c", "i", "s", "l", "q":
            return ObjCMustacheBox(Box(Int(longLongValue)))
        case "C", "I", "S", "L", "Q":
            return ObjCMustacheBox(Box(UInt(unsignedLongLongValue)))
        case "f", "d":
            return ObjCMustacheBox(Box(doubleValue))
        case "B":
            return ObjCMustacheBox(Box(boolValue))
        default:
            NSLog("GRMustache support for NSNumber of type \(objCType) is not implemented yet: value is discarded.")
            return ObjCMustacheBox(Box())
        }
    }
}

extension NSString : ObjCMustacheBoxable {
    
    /**
    Let NSString feed Mustache templates.
    
    See the documentation of String.mustacheBox.
    */
    public override var mustacheBox: ObjCMustacheBox {
        return ObjCMustacheBox(Box(self as String))
    }
}

extension NSSet : ObjCMustacheBoxable {
    
    /**
    Let NSSet feed Mustache templates.
    
    Sets are Mustache collections: they iterate their content.
    
    ::
    
      let template = Template(string: "{{#set}}{{.}},{{/set}}{{^set}}Empty{{/set}}")!
      
      // Renders "3,1,2," (in any order)
      template.render(Box(["set": NSSet(objects: 1,2,3)]))!
      
      // Renders "Empty"
      template.render(Box(["set": NSSet()]))!
    
    Sets can be queried for the following keys:
    
    - count: number of elements in the set
    - anyObject: any object of the set
    
    ::
    
      // Renders "3" and "0"
      template = Template(string: "{{set.count}}")!
      template.render(Box(["set": NSSet(objects: 1,2,3)]))!
      template.render(Box(["set": NSSet()]))!
      
      // Renders "1" or "2" or "3" and ""
      template = Template(string: "{{set.anyObject}}")!
      template.render(Box(["set": NSSet(objects: 1,2,3)]))!
      template.render(Box(["set": NSSet()]))!
    
    In order to render a section if and only if a set is not empty, you can
    query its `count` property, which behaves as the false boolean when zero.
    
    ::
    
      // Renders "Set elements are 3,1,2," and "Set is empty"
      var template = Template(string: "{{#set.count}}Set elements are: {{#set}}{{.}},{{/set}}{{^}}Set is empty{{/}}")!
      template.render(Box(["set": NSSet(objects: 1,2,3)]))!
      template.render(Box(["set": NSSet()]))!
    */
    public override var mustacheBox: ObjCMustacheBox {
        return ObjCMustacheBox(MustacheBox(
            boolValue: (self.count > 0),
            value: self,
            converter: MustacheBox.Converter(arrayValue: { map(GeneratorSequence(NSFastGenerator(self))) { BoxAnyObject($0) } }),
            mustacheSubscript: { (key: String) in
                switch key {
                case "count":
                    return Box(self.count)
                case "anyObject":
                    return BoxAnyObject(self.anyObject())
                default:
                    return Box()
                }
            },
            render: { (info: RenderingInfo, error: NSErrorPointer) in
                if info.enumerationItem {
                    // {{# sets }}...{{/ sets }}
                    return info.tag.renderInnerContent(info.context.extendedContext(Box(self)), error: error)
                } else {
                    // {{ set }}
                    // {{# set }}...{{/ set }}
                    // {{^ set }}...{{/ set }}
                    let boxArray = map(GeneratorSequence(NSFastGenerator(self))) { BoxAnyObject($0) }
                    return renderCollection(boxArray, info, error)
                }
            }))
    }
}


// =============================================================================
// MARK: - Boxing of Core Mustache functions

/**
A function that wraps a value and a SubscriptFunction into a MustacheBox.

:see: SubscriptFunction

::

  struct Person {
      let firstName: String
      let lastName: String
  }

  extension Person : MustacheBoxable {
      var mustacheBox: MustacheBox {
          // Return a Box that wraps our user, and exposes `firstName`,
          // `lastName` and `fullName` to templates:
          return Box(value: self) { (key: String) in
              switch key {
              case "firstName":
                  return Box(self.firstName)
              case "lastName":
                  return Box(self.lastName)
              case "fullName":
                  return Box("\(self.firstName) \(self.lastName)")
              default:
                  return Box()
              }
          }
      }
  }

  // Renders "Tom Selleck"
  let template = Template(string: "{{ person.fullName }}")!
  let person = Person(firstName: "Tom", lastName: "Selleck")
  template.render(Box(["person": Box(person)]))!
*/
public func Box(value: Any, mustacheSubscript: SubscriptFunction) -> MustacheBox {
    return MustacheBox(value: value, mustacheSubscript: mustacheSubscript)
}

/**
A function that wraps a FilterFunction into a MustacheBox.

:see: FilterFunction

::

  let square: FilterFunction = Filter { (x: Int, _) in
      return Box(x * x)
  }

  let template = Template(string: "{{ square(x) }}")!
  template.registerInBaseContext("square", Box(square))

  // Renders "100"
  template.render(Box(["x": 10]))!
*/
public func Box(filter: FilterFunction) -> MustacheBox {
    return MustacheBox(filter: filter)
}

/**
A function that wraps a RenderFunction into a MustacheBox.

RenderFunction is the core function type that lets you implement Mustache
lambdas, and more.

:see: RenderFunction

::

  let foo: RenderFunction = { (_, _) in Rendering("foo") }

  // Renders "foo"
  let template = Template(string: "{{ foo }}")!
  template.render(Box(["foo": Box(foo)]))!
*/
public func Box(render: RenderFunction) -> MustacheBox {
    return MustacheBox(render: render)
}

/**
A function that wraps a WillRenderFunction into a MustacheBox.

:see: WillRenderFunction

::

  let logTags: WillRenderFunction = { (tag: Tag, box: MustacheBox) in
      println("\(tag) will render \(box.value!)")
      return box
  }
  
  // By entering the base context of the template, the logTags function
  // will be notified of all tags.
  let template = Template(string: "{{# user }}{{ firstName }} {{ lastName }}{{/ user }}")!
  template.extendBaseContext(Box(logTags))
  
  // Prints:
  // {{# user }} at line 1 will render { firstName = Errol; lastName = Flynn; }
  // {{ firstName }} at line 1 will render Errol
  // {{ lastName }} at line 1 will render Flynn
  let data = ["user": ["firstName": "Errol", "lastName": "Flynn"]]
  template.render(Box(data))!
*/
public func Box(willRender: WillRenderFunction) -> MustacheBox {
    return MustacheBox(willRender: willRender)
}

/**
A function that wraps a DidRenderFunction into a MustacheBox.

:see: DidRenderFunction

::

  let logRenderings: DidRenderFunction = { (tag: Tag, box: MustacheBox, string: String?) in
      println("\(tag) did render \(box.value!) as `\(string!)`")
  }
  
  // By entering the base context of the template, the logRenderings function
  // will be notified of all tags.
  let template = Template(string: "{{# user }}{{ firstName }} {{ lastName }}{{/ user }}")!
  template.extendBaseContext(Box(logRenderings))
  
  // Renders "Errol Flynn"
  //
  // Prints:
  // {{ firstName }} at line 1 did render Errol as `Errol`
  // {{ lastName }} at line 1 did render Flynn as `Flynn`
  // {{# user }} at line 1 did render { firstName = Errol; lastName = Flynn; } as `Errol Flynn`
  let data = ["user": ["firstName": "Errol", "lastName": "Flynn"]]
  template.render(Box(data))!
*/
public func Box(didRender: DidRenderFunction) -> MustacheBox {
    return MustacheBox(didRender: didRender)
}
