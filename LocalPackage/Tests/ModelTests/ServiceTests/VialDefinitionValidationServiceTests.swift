import Foundation
import Testing

@testable import Model

struct VialDefinitionValidationServiceTests {
    private let sut = VialDefinitionValidationService()

    @Test
    func validate_acceptsValidDefinition() throws {
        let json = """
        {
          "layouts": {
            "keymap": [
              ["0,0", "0,1"]
            ]
          },
          "matrix": {
            "rows": 1,
            "cols": 2
          }
        }
        """
        try sut.validate(json)
    }

    @Test
    func validate_rejectsMissingLayouts() {
        let json = """
        {
          "matrix": {
            "rows": 1,
            "cols": 2
          }
        }
        """

        do {
            try sut.validate(json)
            Issue.record("Expected validation error but succeeded.")
        } catch let error as VialDefinitionValidationError {
            #expect(error == .missingRootField("layouts"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func validate_rejectsInvalidMatrix() {
        let json = """
        {
          "layouts": {
            "keymap": [
              ["0,0"]
            ]
          },
          "matrix": {
            "rows": 0,
            "cols": 0
          }
        }
        """

        do {
            try sut.validate(json)
            Issue.record("Expected validation error but succeeded.")
        } catch let error as VialDefinitionValidationError {
            #expect(error == .invalidMatrix)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
