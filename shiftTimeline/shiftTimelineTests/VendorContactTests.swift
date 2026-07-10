import Foundation
import Testing
@testable import shiftTimeline

/// `VendorContactValidation` exists to mirror the `vendor_contacts` CHECK
/// constraints on the client, so the editor can disable "List in the marketplace"
/// instead of letting the write bounce back as a raw `23514`. These tests pin the
/// client to the SQL, and will fail loudly if either side drifts.
///
/// Server-side (20260709220000_vendor_contact_info.sql):
///   contact_email: `btrim(contact_email) <> '' and position('@' in contact_email) > 1`
///   contact_phone: `length(regexp_replace(contact_phone, '\D', '', 'g')) between 7 and 15`
@Suite("Vendor contact validation")
struct VendorContactTests {

    // MARK: - Email

    @Test("a normal business email is valid")
    func acceptsOrdinaryEmail() {
        #expect(VendorContactValidation.isValidEmail("bookings@energyentertainment.ca"))
    }

    /// `position('@' in x) > 1` — the @ must not be the first character, i.e. there
    /// must be a local part. This is the exact off-by-one the SQL encodes.
    @Test("an email with no local part is rejected")
    func rejectsLeadingAtSign() {
        #expect(VendorContactValidation.isValidEmail("@example.com") == false)
    }

    @Test("an email with no domain is rejected")
    func rejectsTrailingAtSign() {
        #expect(VendorContactValidation.isValidEmail("bookings@") == false)
    }

    @Test("an email with no at-sign is rejected")
    func rejectsMissingAtSign() {
        #expect(VendorContactValidation.isValidEmail("bookings.example.com") == false)
    }

    @Test("blank and whitespace-only emails are rejected")
    func rejectsBlankEmail() {
        #expect(VendorContactValidation.isValidEmail("") == false)
        #expect(VendorContactValidation.isValidEmail("   ") == false)
    }

    /// The server trims before checking, so the client must too — otherwise a
    /// pasted address with a trailing space would disable the toggle for no
    /// visible reason.
    @Test("surrounding whitespace is trimmed, not rejected")
    func trimsEmail() {
        #expect(VendorContactValidation.isValidEmail("  bookings@example.com  "))
    }

    // MARK: - Phone

    /// Digits only, 7...15 — the E.164 range, matching `PhoneAuthService.isValidE164`.
    /// Formatting is the vendor's business; we count digits, not characters.
    @Test("common human phone formats are accepted")
    func acceptsFormattedPhones() {
        #expect(VendorContactValidation.isValidPhone("647-447-2272"))
        #expect(VendorContactValidation.isValidPhone("(647) 447-2272"))
        #expect(VendorContactValidation.isValidPhone("+1 647 447 2272"))
        #expect(VendorContactValidation.isValidPhone("6474472272"))
    }

    @Test("the E.164 digit bounds are inclusive")
    func phoneBoundsAreInclusive() {
        #expect(VendorContactValidation.isValidPhone("1234567"))            // 7
        #expect(VendorContactValidation.isValidPhone("123456789012345"))    // 15
    }

    @Test("too few or too many digits are rejected")
    func rejectsOutOfRangePhones() {
        #expect(VendorContactValidation.isValidPhone("123456") == false)             // 6
        #expect(VendorContactValidation.isValidPhone("1234567890123456") == false)   // 16
    }

    @Test("a phone with no digits is rejected")
    func rejectsDigitlessPhone() {
        #expect(VendorContactValidation.isValidPhone("") == false)
        #expect(VendorContactValidation.isValidPhone("call me") == false)
    }

    // MARK: - Completeness

    /// The listing gate. Both halves are required: a vendor reachable by only one
    /// channel is the gap this whole feature closes.
    @Test("both email and phone are required to be complete")
    func completenessRequiresBoth() {
        #expect(VendorContactValidation.isComplete(email: "a@b.com", phone: "6474472272"))
        #expect(VendorContactValidation.isComplete(email: "a@b.com", phone: "") == false)
        #expect(VendorContactValidation.isComplete(email: "", phone: "6474472272") == false)
        #expect(VendorContactValidation.isComplete(email: "", phone: "") == false)
    }

    // MARK: - DTO wire contract

    /// The DTO is the write payload for `vendor_contacts`; snake_case keys must
    /// match the columns or the upsert 400s.
    @Test("VendorContactDTO encodes the snake_case column names")
    func dtoEncodesColumnNames() throws {
        let id = UUID()
        let dto = VendorContactDTO(
            profileID: id,
            contactEmail: "bookings@example.com",
            contactPhone: "+1 647 447 2272"
        )
        let data = try JSONEncoder().encode(dto)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(json["profile_id"] == id.uuidString)
        #expect(json["contact_email"] == "bookings@example.com")
        #expect(json["contact_phone"] == "+1 647 447 2272")
        #expect(json.count == 3)   // nothing server-managed leaks into the write
    }

    @Test("VendorContactDTO decodes a vendor_contacts row")
    func dtoDecodesRow() throws {
        let id = UUID()
        let json = """
        {
          "profile_id": "\(id.uuidString)",
          "contact_email": "bookings@example.com",
          "contact_phone": "6474472272"
        }
        """
        let dto = try JSONDecoder().decode(VendorContactDTO.self, from: Data(json.utf8))

        #expect(dto.profileID == id)
        #expect(dto.contactEmail == "bookings@example.com")
        #expect(dto.contactPhone == "6474472272")
    }
}
