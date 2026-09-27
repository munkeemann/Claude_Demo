import Foundation

/// A realistic Walmart-style receipt, as OCR text, plus the extraction Claude
/// is expected to produce for it. Used for tests, previews and the offline demo.
///
/// Totals: food 39.42 (untaxed) + household 45.40 (taxed at 6.25% = 2.84)
/// → subtotal 84.82, total 87.66.
public enum SampleReceipt {
    public static let ocrText = """
    WALMART
    Save money. Live better.
    ( 217 ) 555 - 0142
    MANAGER JANE DOE
    2500 N DIRKSEN PKWY
    SPRINGFIELD IL 62702
    ST# 01234 OP# 009876 TE# 12 TR# 04567
    GV WHL MLK 1G    007874237193 F    3.42 N
    BNLS SKNLS CKN BRST    026280100000 F    10.29 N
    2.10 lb @ 4.90 /lb
    BANANAS    000000004011 KF    1.33 N
    2.30 lb @ 0.58 /lb
    MKTSD BBY SPNCH 5Z    068113179215 F    2.48 N
    GV LG EGGS 12CT    007874206784 F    2.89 N
    BARILLA SPGHTI 16Z    007680828059 F    1.79 N
    BARILLA SPGHTI 16Z    007680828059 F    1.79 N
    BUSH BLK BEANS 15Z    003940001991 F    3.96 N
    4 @ 0.99
    TLMK SHRP CHDR 8Z    007205312345 F    4.49 N
    RAOS MARINARA 24Z    074767300004 F    6.98 N
    DAWN ULT DISH 19OZ    003700097341    3.47 X
    CHRMN ULT SFT 12MR    003700012345    15.97 X
    BNTY SAS 6DBL    003700054321    13.49 X
    INSTANT SAVINGS    1.50-
    TIDE ORIG 92OZ    003700087654    13.97 X
    SUBTOTAL    84.82
    TAX 1    6.250 %    2.84
    TOTAL    87.66
    VISA TEND    87.66
    VISA CREDIT **** **** **** 4821
    CHANGE DUE    0.00
    # ITEMS SOLD 17
    TC# 1234 5678 9012 3456 7890
    09/21/26    14:32:07
    """

    /// Canned structured output for `ocrText`, stored as the JSON Claude
    /// returns so decoding is exercised too.
    public static let extractionJSON = """
    {
      "storeName": "Walmart",
      "purchaseDate": "2026-09-21",
      "currency": "USD",
      "items": [
        {"rawText": "GV WHL MLK 1G", "name": "Whole Milk", "brand": "Great Value", "category": "dairy",
         "quantity": 1, "unit": "gal", "packageSize": "1 gal", "totalPrice": 3.42, "location": "fridge",
         "shelfLifeDays": 7, "confidence": "high"},
        {"rawText": "BNLS SKNLS CKN BRST", "name": "Boneless Skinless Chicken Breast", "brand": null,
         "category": "meat", "quantity": 2.1, "unit": "lb", "packageSize": null, "totalPrice": 10.29,
         "location": "fridge", "shelfLifeDays": 2, "confidence": "high"},
        {"rawText": "BANANAS", "name": "Bananas", "brand": null, "category": "produce", "quantity": 2.3,
         "unit": "lb", "packageSize": null, "totalPrice": 1.33, "location": "pantry", "shelfLifeDays": 5,
         "confidence": "high"},
        {"rawText": "MKTSD BBY SPNCH 5Z", "name": "Baby Spinach", "brand": "Marketside", "category": "produce",
         "quantity": 1, "unit": "bag", "packageSize": "5 oz", "totalPrice": 2.48, "location": "fridge",
         "shelfLifeDays": 5, "confidence": "high"},
        {"rawText": "GV LG EGGS 12CT", "name": "Large Eggs", "brand": "Great Value", "category": "eggs",
         "quantity": 1, "unit": "dozen", "packageSize": "12 ct", "totalPrice": 2.89, "location": "fridge",
         "shelfLifeDays": 28, "confidence": "high"},
        {"rawText": "BARILLA SPGHTI 16Z", "name": "Spaghetti", "brand": "Barilla", "category": "grains",
         "quantity": 2, "unit": "box", "packageSize": "16 oz", "totalPrice": 3.58, "location": "pantry",
         "shelfLifeDays": null, "confidence": "high"},
        {"rawText": "BUSH BLK BEANS 15Z", "name": "Black Beans", "brand": "Bush's", "category": "canned",
         "quantity": 4, "unit": "can", "packageSize": "15 oz", "totalPrice": 3.96, "location": "pantry",
         "shelfLifeDays": null, "confidence": "high"},
        {"rawText": "TLMK SHRP CHDR 8Z", "name": "Sharp Cheddar Cheese", "brand": "Tillamook", "category": "cheese",
         "quantity": 8, "unit": "oz", "packageSize": "8 oz", "totalPrice": 4.49, "location": "fridge",
         "shelfLifeDays": 42, "confidence": "medium"},
        {"rawText": "RAOS MARINARA 24Z", "name": "Marinara Sauce", "brand": "Rao's", "category": "condiments",
         "quantity": 1, "unit": "jar", "packageSize": "24 oz", "totalPrice": 6.98, "location": "pantry",
         "shelfLifeDays": null, "confidence": "high"},
        {"rawText": "DAWN ULT DISH 19OZ", "name": "Dish Soap", "brand": "Dawn", "category": "cleaning",
         "quantity": 1, "unit": "bottle", "packageSize": "19.4 fl oz", "totalPrice": 3.47, "location": "cleaning",
         "shelfLifeDays": null, "confidence": "high"},
        {"rawText": "CHRMN ULT SFT 12MR", "name": "Toilet Paper Mega Rolls", "brand": "Charmin",
         "category": "paperGoods", "quantity": 1, "unit": "pack", "packageSize": "12 rolls", "totalPrice": 15.97,
         "location": "bathroom", "shelfLifeDays": null, "confidence": "high"},
        {"rawText": "BNTY SAS 6DBL", "name": "Paper Towels", "brand": "Bounty", "category": "paperGoods",
         "quantity": 1, "unit": "pack", "packageSize": "6 double rolls", "totalPrice": 11.99, "location": "cleaning",
         "shelfLifeDays": null, "confidence": "medium"},
        {"rawText": "TIDE ORIG 92OZ", "name": "Laundry Detergent", "brand": "Tide", "category": "laundry",
         "quantity": 1, "unit": "bottle", "packageSize": "92 fl oz", "totalPrice": 13.97, "location": "cleaning",
         "shelfLifeDays": null, "confidence": "high"}
      ],
      "subtotal": 84.82,
      "tax": 2.84,
      "total": 87.66
    }
    """

    public static let extraction: ReceiptExtraction = {
        do {
            return try JSONDecoder().decode(ReceiptExtraction.self, from: Data(extractionJSON.utf8))
        } catch {
            preconditionFailure("SampleReceipt.extractionJSON is invalid: \(error)")
        }
    }()
}
