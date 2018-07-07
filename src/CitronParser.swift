/*

Lemon: LALR(1) parser generator that generates a parser in C

    Author disclaimed copyright

    Public domain code.

Citron: Modifications to Lemon to generate a parser in Swift

    Copyright (C) 2017 Roopesh Chander <roop@roopc.net>

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/


// This file is part of the Citron parser generator.
//
// This file defines the CitronParser protocol. Citron shall
// auto-generate a class conforming to this protocol based on the input
// grammar.
//
// The CitronParser protocol defined below is compatible with Swift code
// generated using Citron version 1.x.

protocol CitronParser: class {

    // Types

    // Symbol code, state number and rule number are typically
    // mapped to UInt8. However, if there are more than 256 symbols, states
    // or rules respectively, they will get mapped to bigger integer types.
    associatedtype CitronSymbolCode: BinaryInteger // YYCODETYPE in lemon
    associatedtype CitronStateNumber: BinaryInteger
    associatedtype CitronRuleNumber: BinaryInteger

    // Token code: An enum representing the terminals. The raw value shall
    // be equal to the symbol code representing the terminal.
    associatedtype CitronTokenCode: RawRepresentable where CitronTokenCode.RawValue == CitronSymbolCode

    // Token: The type representing a terminal, defined using %token_type in the grammar.
    // ParseTOKENTYPE in lemon.
    associatedtype CitronToken

    // Symbol: An enum type representing any terminal or non-terminal symbol.
    // YYMINORTYPE in lemon.
    associatedtype CitronSymbol

    // Result: The type representing the start symbol of the grammar
    associatedtype CitronResult

    // Counts

    var yyNumberOfSymbols: Int { get } // YYNOCODE in lemon
    var yyNumberOfStates: Int { get } // YYNSTATE in lemon

    // Action tables

    // The action (CitronParsingAction) is applicable only if
    // the look ahead symbol (CitronSymbolCode) matches
    var yyLookaheadAction: [(CitronSymbolCode, CitronParsingAction)] { get } // yy_action + yy_lookahead in lemon

    var yyShiftUseDefault: Int { get } // YY_SHIFT_USE_DFLT in lemon
    var yyShiftOffsetMin: Int { get } // YY_SHIFT_MIN in lemon
    var yyShiftOffsetMax: Int { get } // YY_SHIFT_MAX in lemon
    var yyShiftOffset: [Int] { get } // yy_shift_ofst in lemon

    var yyReduceUseDefault: Int { get } // YY_REDUCE_USE_DFLT in lemon
    var yyReduceOffsetMin: Int { get } // YY_REDUCE_MIN in lemon
    var yyReduceOffsetMax: Int { get } // YY_REDUCE_MAX in lemon
    var yyReduceOffset: [Int] { get } // yy_reduce_ofst in lemon

    var yyDefaultAction: [CitronParsingAction] { get } // yy_default in lemon

    // Fallback

    var yyHasFallback: Bool { get } // YYFALLBACK in lemon
    var yyFallback: [CitronSymbolCode] { get } // yyFallback in lemon

    // Wildcard

    var yyWildcard: CitronSymbolCode? { get }

    // Rules

    var yyRuleInfo: [(lhs: CitronSymbolCode, nrhs: UInt)] { get }

    // Stack

    var yyStack: [(stateOrRule: CitronStateOrRule, symbolCode: CitronSymbolCode,
        symbol: CitronSymbol)] { get set }
    var maxStackSize: Int? { get set }
    var maxAttainedStackSize: Int { get set }

    // Tracing

    var isTracingEnabled: Bool { get set }
    var yySymbolName: [String] { get } // yyTokenName in lemon
    var yyRuleText: [String] { get } // yyRuleName in lemon

    // Functions that shall be defined in the autogenerated code

    func yyTokenToSymbol(_ token: CitronToken) -> CitronSymbol
    func yyInvokeCodeBlockForRule(ruleNumber: CitronRuleNumber) throws -> CitronSymbol
    func yyUnwrapResultFromSymbol(_ symbol: CitronSymbol) -> CitronResult

    // Error handling

    typealias CitronParserError = _CitronParserError<CitronToken, CitronTokenCode>
    typealias CitronParsingAction = _CitronParsingAction<CitronStateNumber, CitronRuleNumber>
    typealias CitronStateOrRule = _CitronStateOrRule<CitronStateNumber, CitronRuleNumber>
}

// Error handling

enum _CitronParserError<Token, TokenCode>: Error {
    case syntaxErrorAt(token: Token, tokenCode: TokenCode)
    case unexpectedEndOfInput
    case stackOverflow
}

// Parser actions and states

enum _CitronParsingAction<StateNumber: BinaryInteger, RuleNumber: BinaryInteger> {
    case SH(StateNumber) // Shift token, then go to state <state>
    case RD(RuleNumber)  // Reduce with rule number <rule>
    case SR(RuleNumber)  // Shift token, then reduce with rule number <rule>
    case ERROR
    case ACCEPT
}

enum _CitronStateOrRule<StateNumber: BinaryInteger, RuleNumber: BinaryInteger> {
    case state(StateNumber)
    case rule(RuleNumber)
}

// Parsing interface

extension CitronParser {
    func consume(token: CitronToken, code tokenCode: CitronTokenCode) throws {
        let symbolCode = tokenCode.rawValue
        tracePrint("Input:", symbolNameFor(code:symbolCode))
        LOOP: while (!yyStack.isEmpty) {
            let action = yyFindShiftAction(lookAhead: symbolCode)
            switch (action) {
            case .SH(let s):
                try yyShift(state: s, symbolCode: symbolCode, token: token)
                break LOOP
            case .SR(let r):
                try yyShiftReduce(rule: r, symbolCode: symbolCode, token: token)
                break LOOP
            case .RD(let r):
                let resultSymbol = try yyReduce(rule: r)
                assert(resultSymbol == nil) // Can be non-nil only in endParsing()
                continue LOOP
            case .ERROR:
                throw CitronParserError.syntaxErrorAt(token: token, tokenCode: tokenCode)
            default:
                fatalError("Unexpected action")
            }
        }
        traceStack()
    }

    func endParsing() throws -> CitronResult {
        tracePrint("End of input")
        LOOP: while (!yyStack.isEmpty) {
            let action = yyFindShiftAction(lookAhead: 0)
            switch (action) {
            case .RD(let r):
                let resultSymbol = try yyReduce(rule: r)
                if let resultSymbol = resultSymbol {
                    tracePrint("Parse successful")
                    return yyUnwrapResultFromSymbol(resultSymbol)
                }
                continue LOOP
            case .ERROR:
                throw CitronParserError.unexpectedEndOfInput
            default:
                fatalError("Unexpected action")
            }
        }
        fatalError("Unexpected stack underflow")
    }

    func reset() {
        tracePrint("Resetting the parser")
        while (yyStack.count > 1) {
            yyPop()
        }
    }
}

// Private methods

private extension CitronParser {

    func yyPush(stateOrRule: CitronStateOrRule, symbolCode: CitronSymbolCode, symbol: CitronSymbol) throws {
        if (maxStackSize != nil && yyStack.count >= maxStackSize!) {
            // Can't grow stack anymore
            throw CitronParserError.stackOverflow
        }
        yyStack.append((stateOrRule: stateOrRule, symbolCode: symbolCode, symbol: symbol))
        if (maxAttainedStackSize < yyStack.count) {
            maxAttainedStackSize = yyStack.count
        }
    }

    func yyPop() {
        let last = yyStack.popLast()
        if let last = last {
            tracePrint("Popping", symbolNameFor(code:last.symbolCode))
        }
    }

    func yyPopAll() {
        while (!yyStack.isEmpty) {
            yyPop()
        }
    }

    func yyFindShiftAction(lookAhead la: CitronSymbolCode) -> CitronParsingAction {
        guard (!yyStack.isEmpty) else { fatalError("Unexpected empty stack") }

        let state: CitronStateNumber
        switch (yyStack.last!.stateOrRule) {
        case .rule(let r):
            return .RD(r)
        case .state(let s):
            state = s
        }

        var i: Int = 0
        var lookAhead = la
        while (true) {
            assert(Int(state) < yyShiftOffset.count)
            assert(lookAhead < yyNumberOfSymbols)
            i = yyShiftOffset[Int(state)] + Int(lookAhead)

            // Check action table
            if (i >= 0 && i < yyLookaheadAction.count) {
                let (actionLookahead, action) = yyLookaheadAction[i]
                if (actionLookahead == lookAhead) {
                    return action // Pick action from action table
                }
            }

            // Check for fallback
            if let fallback = yyFallback[safe: lookAhead], fallback > 0 {
                tracePrint("Fallback:", symbolNameFor(code: lookAhead), "=>", symbolNameFor(code:fallback))
                precondition((yyFallback[safe: fallback] ?? -1) == 0, "Fallback loop detected")
                lookAhead = fallback
                continue
            }

            // Check for wildcard
            if let yyWildcard = yyWildcard {
                let wildcard = yyWildcard
                let j = i - Int(lookAhead) + Int(wildcard)
                let (actionLookahead, action) = yyLookaheadAction[j]
                if ((yyShiftOffsetMin + Int(wildcard) >= 0 || j >= 0) &&
                    (yyShiftOffsetMax + Int(wildcard) < yyLookaheadAction.count || j < yyLookaheadAction.count) &&
                    (actionLookahead == wildcard && lookAhead > 0)) {
                    tracePrint("Wildcard:", symbolNameFor(code: lookAhead), "=>", symbolNameFor(code: wildcard))
                    return action
                }
            }

            // Pick the default action for this state.
            return yyDefaultAction[Int(state)]
        }
    }

    func yyFindReduceAction(state: CitronStateNumber, lookAhead: CitronSymbolCode) -> CitronParsingAction {
        assert(Int(state) < yyReduceOffset.count)
        var i = yyReduceOffset[Int(state)]

        assert(i != yyReduceUseDefault)
        assert(lookAhead < yyNumberOfSymbols)

        i += Int(lookAhead)
        let (actionLookahead, action) = yyLookaheadAction[i]

        assert(i >= 0 && i < yyLookaheadAction.count)
        assert(actionLookahead == lookAhead)

        return action
    }

    func yyShift(state: CitronStateNumber, symbolCode: CitronSymbolCode, token: CitronToken) throws {
        tracePrint("Shift: Shift", symbolNameFor(code:symbolCode))
        tracePrint("       and go to state", "\(state)")
        try yyPush(stateOrRule: .state(state), symbolCode: symbolCode, symbol: yyTokenToSymbol(token))
    }

    func yyShiftReduce(rule: CitronRuleNumber, symbolCode: CitronSymbolCode, token: CitronToken) throws {
        tracePrint("ShiftReduce: Shift", symbolNameFor(code:symbolCode))
        tracePrint("       and reduce with rule: ", "\(rule)")
        try yyPush(stateOrRule: .rule(rule), symbolCode: symbolCode, symbol: yyTokenToSymbol(token))
    }

    // yyReduce: Reduces using the specified rule number.
    // If the parse is accepted, returns the result symbol, else returns nil.
    func yyReduce(rule ruleNumber: CitronRuleNumber) throws -> CitronSymbol? {
        assert(ruleNumber < yyRuleInfo.count)
        guard (!yyStack.isEmpty) else { fatalError("Unexpected empty stack") }
        tracePrint("Reducing with rule:", yyRuleText[Int(ruleNumber)])

        let resultSymbol = try yyInvokeCodeBlockForRule(ruleNumber: ruleNumber)

        let ruleInfo = yyRuleInfo[Int(ruleNumber)]
        let lhsSymbolCode = ruleInfo.lhs
        let numberOfRhsSymbols = ruleInfo.nrhs
        assert(yyStack.count > numberOfRhsSymbols)

        for _ in (0 ..< numberOfRhsSymbols) {
            yyPop()
        }

        return try yyPerformReduceAction(symbol: resultSymbol, code: lhsSymbolCode)
    }

    func yyPerformReduceAction(symbol resultSymbol: CitronSymbol, code lhsSymbolCode: CitronSymbolCode) throws -> CitronSymbol? {

        guard case .state(let stateInStack) = yyStack.last!.stateOrRule else {
            fatalError("Expecting state got rule") // FIXME: Is this correct?
        }
        let action = yyFindReduceAction(state: stateInStack, lookAhead: lhsSymbolCode)

        let stateOrRule: CitronStateOrRule
        switch (action) {
        case .SH(let s): stateOrRule = .state(s)
        case .SR(_): fatalError("Unexpected shift-reduce action after a reduce")
        // There are no SHIFTREDUCE actions on nonterminals because the table
        // generator has simplified them to pure REDUCE actions
        case .RD(let r): stateOrRule = .rule(r)
        case .ERROR: fatalError("Unexpected error action after a reduce")
        // It is not possible for a REDUCE to be followed by an error.
        case .ACCEPT: return resultSymbol
        }

        try yyPush(stateOrRule: stateOrRule, symbolCode: lhsSymbolCode, symbol: resultSymbol)
        tracePrint("Shift:", symbolNameFor(code:lhsSymbolCode))
        if (isTracingEnabled) {
            switch (stateOrRule) {
            case .state(let s):
                tracePrint("       and go to state", "\(s)")
            case .rule(let r):
                tracePrint("       and reduce with rule", "\(r)")
            }
        }
        traceStack()
        return nil
    }
}

// Private helpers

private extension CitronParser {
    func tracePrint(_ msg: String) {
        if (isTracingEnabled) {
            print("\(msg)")
        }
    }

    func tracePrint(_ msg: String, _ closure: @autoclosure () -> CustomDebugStringConvertible) {
        if (isTracingEnabled) {
            print("\(msg) \(closure())")
        }
    }

    func tracePrint(_ msg: String, _ closure: @autoclosure () -> CustomDebugStringConvertible,
                    _ msg2: String, _ closure2: @autoclosure () -> CustomDebugStringConvertible) {
        if (isTracingEnabled) {
            print("\(msg) \(closure()) \(msg2) \(closure2())")
        }
    }

    func symbolNameFor(code i: CitronSymbolCode) -> String {
        if (i > 0 && i < yySymbolName.count) { return yySymbolName[Int(i)] }
        return "?"
    }

    func traceStack() {
        if (isTracingEnabled) {
            print("STACK contents:")
            for (i, e) in yyStack.enumerated() {
                print("    \(i): (stateOrRule: \(e.stateOrRule), symbol: \(symbolNameFor(code:e.symbolCode)) [\(e.symbolCode)])")
            }
        }
    }
}

private extension Array {
    subscript<I: BinaryInteger>(safe i: I) -> Element? {
        get {
            let index = Int(i)
            return index < self.count ? self[index] : nil
        }
    }
}

