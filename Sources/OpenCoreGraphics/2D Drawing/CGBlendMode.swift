import Foundation

/// Compositing operations for images.
/// 
/// These blend mode constants represent the Porter-Duff blend modes. 
/// The symbols in the equations for these blend modes are:
/// - R is the premultiplied result
/// - S is the source color, and includes alpha
/// - D is the destination color, and includes alpha
/// - Ra, Sa, and Da are the alpha components of R, S, and D
/// 
/// You can find more information on blend modes, including examples of images produced using them, and many mathematical descriptions of the modes, in PDF Reference, Fourth Edition, Version 1.5, Adobe Systems, 
/// Inc. If you are a former QuickDraw developer, it may be helpful for you to think of blend modes as an alternative to transfer modes
public enum CGBlendMode {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case clear
    case copy
    case sourceIn
    case sourceOut
    case sourceAtop
    case destinationOver
    case destinationIn
    case destinationOut
    case destinationAtop
    case xor
    case plusDarker
    case plusLighter
}