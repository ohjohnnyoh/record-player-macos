#!/usr/bin/env swift
// Рисует иконку приложения (1024x1024 PNG) средствами CoreGraphics.
// Запуск: swift tools/makeicon.swift <выход.png> [логотип.png]
//
// Логотип ожидается как тёмная фигура на светлом фоне без альфа-канала:
// фон вырезается по яркости, фигура перекрашивается в белый и садится
// на тёмный сквиркл. Если файла нет — рисуется запасная иконка из дуг.

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let logoPath: String? = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

let size = 1024
let s = CGFloat(size)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

// MARK: - Фон

let inset: CGFloat = s * 0.085
let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let squircle = CGPath(roundedRect: rect, cornerWidth: s * 0.222, cornerHeight: s * 0.222, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bgColors = [
    CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
    CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
}
ctx.restoreGState()

// MARK: - Логотип

/// Превращает тёмную-на-светлом картинку в белую фигуру с прозрачным фоном
/// и возвращает её вместе с границами непрозрачной области.
func whiteSilhouette(from image: CGImage) -> (image: CGImage, bounds: CGRect)? {
    let w = image.width, h = image.height
    var source = [UInt8](repeating: 0, count: w * h * 4)
    guard let readCtx = CGContext(
        data: &source, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    // Подкладываем белый: если у исходника есть альфа, прозрачное станет фоном.
    readCtx.setFillColor(CGColor(gray: 1, alpha: 1))
    readCtx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    readCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var output = [UInt8](repeating: 0, count: w * h * 4)
    var minX = w, minY = h, maxX = -1, maxY = -1

    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            // Яркость по Rec. 709; фигура тёмная, значит альфа = 1 - яркость.
            let luma = (Double(source[i]) * 0.2126 + Double(source[i + 1]) * 0.7152
                        + Double(source[i + 2]) * 0.0722) / 255.0
            let alpha = max(0, min(1, (1.0 - luma - 0.06) / 0.80))   // небольшой порог против серой каймы
            let a = UInt8(alpha * 255)
            // premultipliedLast: белый цвет, умноженный на альфу.
            output[i] = a; output[i + 1] = a; output[i + 2] = a; output[i + 3] = a
            if a > 24 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }

    guard let outCtx = CGContext(
        data: &output, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let result = outCtx.makeImage() else { return nil }

    let bounds = CGRect(
        x: CGFloat(minX), y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)
    )
    return (result, bounds)
}

var drewLogo = false

if let logoPath,
   FileManager.default.fileExists(atPath: logoPath),
   let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: logoPath) as CFURL, nil),
   let logo = CGImageSourceCreateImageAtIndex(source, 0, nil),
   let (silhouette, contentBounds) = whiteSilhouette(from: logo) {

    // Обрезаем по содержимому, чтобы поля исходника не съедали иконку.
    let cropped = silhouette.cropping(to: contentBounds) ?? silhouette
    let logoW = CGFloat(cropped.width), logoH = CGFloat(cropped.height)

    // Вписываем в 62% ширины и 46% высоты — запас, чтобы широкий вордмарк дышал.
    let maxW = s * 0.62, maxH = s * 0.46
    let scale = min(maxW / logoW, maxH / logoH)
    let drawW = logoW * scale, drawH = logoH * scale
    let drawRect = CGRect(
        x: (s - drawW) / 2,
        y: (s - drawH) / 2 - s * 0.005,
        width: drawW, height: drawH
    )

    // Мягкая тень, чтобы белое не сливалось с фоном на светлых обоях Dock.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(gray: 0, alpha: 0.55))
    ctx.draw(cropped, in: drawRect)
    ctx.restoreGState()
    drewLogo = true
}

if !drewLogo {
    // Запасной вариант: концентрические дуги «эфира» с красным ядром.
    let center = CGPoint(x: s / 2, y: s / 2)
    ctx.setLineCap(.round)
    for (index, radius) in [s * 0.17, s * 0.245, s * 0.32].enumerated() {
        ctx.setLineWidth(s * 0.032)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95 - Double(index) * 0.26))
        for startAngle in [-CGFloat.pi / 4, CGFloat.pi * 3 / 4] {
            ctx.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: startAngle + .pi / 2, clockwise: false)
            ctx.strokePath()
        }
    }
    ctx.setFillColor(CGColor(red: 0.93, green: 0.16, blue: 0.20, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - s * 0.072, y: center.y - s * 0.072,
                               width: s * 0.144, height: s * 0.144))
}

// Тонкая световая обводка по краю сквиркла.
ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
ctx.setLineWidth(s * 0.006)
ctx.strokePath()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
print("icon written: \(outputPath) (логотип: \(drewLogo ? "да" : "запасной"))")
