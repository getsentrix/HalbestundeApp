import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ScoreModelTests.allTests),
        testCase(MusicXMLParserTests.allTests),
        testCase(PracticeControlsTests.allTests),
        testCase(OMRStaffDetectorTests.allTests),
        testCase(AudioSchedulerTests.allTests)
    ]
}
#endif
