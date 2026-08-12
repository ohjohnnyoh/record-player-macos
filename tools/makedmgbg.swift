#!/usr/bin/env swift
// Рисует фон окна установщика: подпись сверху и стрелка между иконками.
// Запуск: swift tools/makedmgbg.swift <выход.png> [масштаб]
//
// Иконки Finder расставляет поверх этого фона, поэтому середина оставлена пустой:
// слева окажется приложение, справа — папка «Программы», стрелка ровно между ними.

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let scale = CommandLine.arguments.count > 2 ? (Double(CommandLine.arguments[2]) ?? 1) : 1

// Логический размер окна установщика.
let W = 640.0, H = 400.0
let pxW = Int(W * scale), pxH = Int(H * scale)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: pxW, height: pxH,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

ctx.scaleBy(x: scale, y: scale)

// MARK: - Фон

if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.10, green: 0.10, blue: 0.115, alpha: 1),
        CGColor(red: 0.045, green: 0.045, blue: 0.055, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
}

// Мягкое пятно за центром, чтобы стрелка не висела в пустоте.
if let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.045),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray,
    locations: [0, 1]
) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: W / 2, y: 175), startRadius: 0,
        endCenter: CGPoint(x: W / 2, y: 175), endRadius: 240,
        options: []
    )
}

// MARK: - Стрелка

// Finder ставит иконку по центру ячейки, а в ячейку входит и подпись под ней,
// поэтому графический центр иконки примерно на 10 пунктов выше точки позиции.
// Позиция иконок — 235 сверху, значит их середина приходится на 175 снизу.
let arrowY = 175.0
let arrowFrom = 262.0, arrowTo = 378.0
let headLength = 30.0, headHalf = 15.0
let shaftWidth = 8.0
let arrowColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.5)

ctx.setFillColor(arrowColor)

// Древко со скруглёнными краями.
let shaft = CGRect(
    x: arrowFrom, y: arrowY - shaftWidth / 2,
    width: arrowTo - headLength - arrowFrom, height: shaftWidth
)
ctx.addPath(CGPath(roundedRect: shaft, cornerWidth: shaftWidth / 2, cornerHeight: shaftWidth / 2, transform: nil))
ctx.fillPath()

// Наконечник.
let head = CGMutablePath()
head.move(to: CGPoint(x: arrowTo, y: arrowY))
head.addLine(to: CGPoint(x: arrowTo - headLength, y: arrowY + headHalf))
head.addLine(to: CGPoint(x: arrowTo - headLength, y: arrowY - headHalf))
head.closeSubpath()
ctx.addPath(head)
ctx.fillPath()

// MARK: - Подписи

let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

func drawCentered(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha)
    ]
    let string = text as NSString
    let size = string.size(withAttributes: attrs)
    string.draw(at: NSPoint(x: (W - size.width) / 2, y: y), withAttributes: attrs)
}

drawCentered("Record", y: H - 78, size: 23, weight: .semibold, alpha: 0.95)
drawCentered("Перетащите приложение в папку «Программы»", y: H - 108, size: 13, weight: .regular, alpha: 0.55)

NSGraphicsContext.restoreGraphicsState()

// MARK: - Запись

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
print("background written: \(outputPath) (\(pxW)x\(pxH))")
