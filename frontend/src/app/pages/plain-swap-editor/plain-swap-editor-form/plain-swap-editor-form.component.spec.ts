import { HttpClient } from "@angular/common/http";
import { fakeAsync, tick } from "@angular/core/testing";
import { FormBuilder } from "@angular/forms";
import { MatDialog, MatDialogRef } from "@angular/material/dialog";
import { MatSnackBar } from "@angular/material/snack-bar";
import { Observable, of } from "rxjs";
import { DefaultService, PlainSwapEditorService, PlainSwapOperationRequest } from "src/app/openapi";
import { counterparties } from "src/app/shared/form-data/counterparties";
import { PlainSwapEditorFormComponent } from "./plain-swap-editor-form.component";

class EditorUnderTest extends PlainSwapEditorFormComponent {
  get form() { return this.swapForm; }
}

describe("PlainSwapEditorFormComponent API requests", () => {
  let component: EditorUnderTest;
  let service: jasmine.SpyObj<PlainSwapEditorService>;
  let dialog: jasmine.SpyObj<MatDialog>;

  beforeEach(() => {
    service = jasmine.createSpyObj<PlainSwapEditorService>("service", ["getSavedContracts"]);
    dialog = jasmine.createSpyObj<MatDialog>("dialog", ["open"]);
    component = new EditorUnderTest(
      jasmine.createSpyObj<MatSnackBar>("snackBar", ["open"]),
      service,
      jasmine.createSpyObj<DefaultService>("defaultService", ["infoFinmath"]),
      jasmine.createSpyObj<HttpClient>("http", ["post"]),
      dialog,
      new FormBuilder()
    );
    component.ngOnInit();
    spyOn(component, "pushPricingRequest");
    component.form.patchValue({
      firstCounterparty: counterparties[0].bicCode,
      secondCounterparty: counterparties[1].bicCode,
      fixedPayingParty: counterparties[1].bicCode,
      floatingPayingParty: counterparties[0].bicCode,
      notionalAmount: 1_000_000,
      fixedRate: 2.5,
      tradeDate: new Date(2026, 0, 1),
      effectiveDate: new Date(2026, 0, 2),
      terminationDate: new Date(2027, 0, 2),
      fixedPaymentFrequency: "Annual",
      floatingPaymentFrequency: "Semiannual",
      floatingRateIndex: "EURIBOR 6M",
    }, { emitEvent: false });
  });

  it("sends required backend settings and derives the fixed payer's party ID", () => {
    const request = component.mapRequest();
    expect(request.tradeType).toBe("SDCPledgedBalance");
    expect(request.dailySettlementTime).toBe("12:00");
    expect(request.marketDataProvider).toBe("refinitiv");
    expect(request.receiverPartyID).toBe("party1");
    expect(request.fixPayerPartyID).toBe("party2");
    expect(request.firstCounterparty.dltAddress).toBe(counterparties[0].dltAddress);
    expect(request.floatingFixingDayOffset).toBe(-2);
    expect(request.tradeDate).toBe("2026-01-01T00:00:00.000Z");
    expect("currentGenerator" in request).toBeFalse();

    component.form.get("fixedPayingParty")!.setValue(counterparties[0].bicCode, { emitEvent: false });
    expect(component.mapRequest().fixPayerPartyID).toBe("party1");
  });

  it("loads optional leg settings and preserves saved contract metadata and currency", fakeAsync(() => {
    const saved: PlainSwapOperationRequest = {
      ...component.mapRequest(),
      currency: "USD",
      dailySettlementTime: "16:30",
      marketDataProvider: "refinitiv",
      receiverPartyID: "party2",
      uniqueTradeIdentifier: "saved-trade",
      fixedRollConvention: "EOM",
      floatingRollConvention: "15",
      fixedPayingParty: undefined,
      floatingPayingParty: undefined,
      fixedPaymentFrequency: undefined,
      floatingPaymentFrequency: undefined,
      floatingFixingDayOffset: undefined,
    };
    const getSavedContracts = service.getSavedContracts as jasmine.Spy<() => Observable<string[]>>;
    getSavedContracts.and.returnValue(of([]));
    dialog.open.and.returnValue({ afterClosed: () => of(saved) } as MatDialogRef<unknown>);

    component.openSaveLoadDialog();
    tick(500);
    const restored = component.mapRequest();
    expect(restored.currency).toBe("USD");
    expect(restored.dailySettlementTime).toBe("16:30");
    expect(restored.receiverPartyID).toBe("party2");
    expect(restored.uniqueTradeIdentifier).toBe("saved-trade");
    expect(restored.fixedRollConvention).toBe("EOM");
    expect(restored.floatingRollConvention).toBe("15");
    expect(restored.fixPayerPartyID).toBe("party2");
    expect(restored.fixedPayingParty).toBe(counterparties[1]);
    expect(restored.floatingPayingParty).toBe(counterparties[0]);
    expect(restored.fixedPaymentFrequency?.fullName).toBe("Annual");
    expect(restored.floatingPaymentFrequency?.fullName).toBe("Semiannual");
    expect(restored.floatingFixingDayOffset).toBe(-2);
  }));

  it("retains loaded party details, unfamiliar BICs and dates across repeated saves", fakeAsync(() => {
    let saved: PlainSwapOperationRequest = {
      ...component.mapRequest(),
      firstCounterparty: {
        ...counterparties[0],
        fullName: "Saved Party One",
        dltAddress: "0x1111111111111111111111111111111111111111",
        baseUrl: "https://party-one.example/",
      },
      secondCounterparty: {
        bicCode: "NEWPDEFF",
        fullName: "New Counterparty",
        dltAddress: "0x2222222222222222222222222222222222222222",
        baseUrl: "https://new-party.example/",
      },
      fixedPayingParty: undefined,
      floatingPayingParty: undefined,
      tradeDate: "2026-01-01T00:00:00.000Z",
      effectiveDate: "2026-07-01T00:00:00.000Z",
      terminationDate: "2027-07-01T00:00:00.000Z",
    };
    const expected = saved;
    const getSavedContracts = service.getSavedContracts as jasmine.Spy<() => Observable<string[]>>;
    getSavedContracts.and.returnValue(of([]));
    dialog.open.and.returnValue({ afterClosed: () => of(saved) } as MatDialogRef<unknown>);

    for (let roundTrip = 0; roundTrip < 2; roundTrip++) {
      component.openSaveLoadDialog();
      tick(500);
      saved = component.mapRequest();
      expect(saved.firstCounterparty).toEqual(expected.firstCounterparty);
      expect(saved.secondCounterparty).toEqual(expected.secondCounterparty);
      expect(saved.fixedPayingParty).toEqual(expected.secondCounterparty);
      expect(saved.floatingPayingParty).toEqual(expected.firstCounterparty);
      expect(saved.tradeDate).toBe(expected.tradeDate);
      expect(saved.effectiveDate).toBe(expected.effectiveDate);
      expect(saved.terminationDate).toBe(expected.terminationDate);
    }
    expect(counterparties[0].fullName).toBe("Party One Bank");
  }));
});
