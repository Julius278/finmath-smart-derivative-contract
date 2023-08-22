import { FrontendItemSpec, PaymentFrequency } from "src/app/openapi";
import { DayCountFraction } from "../form-data/day-count-fractions";
import { FixingDayOffset } from "../form-data/fixing-day-offsets";

export interface PlainSwapEditorGenerator {
  name: string;
  fileName: string;
  defaultSymbolsList: FrontendItemSpec[];
  indexName: string;
  fixedPaymentFrequency: PaymentFrequency;
  floatingPaymentFrequency: PaymentFrequency;
  floatingFixingDayOffset: FixingDayOffset;
  fixedDayCountFraction: DayCountFraction;
  floatingDayCountFraction: DayCountFraction;
}

export const plainSwapEditorGenerators: PlainSwapEditorGenerator[] = [
  {
    name: "EUR-EURIBOR Y/S",
    fileName: "generators/eur_euribor_y_s_with_fixings.xml",
    indexName: "EURIBOR 6M",
    fixedPaymentFrequency: {
      period: "Y",
      periodMultiplier: 1,
      fullName: "Annual",
    },
    floatingPaymentFrequency: {
      period: "M",
      periodMultiplier: 6,
      fullName: "Semiannual",
    },
    fixedDayCountFraction: {
      id: "30E/360",
      fullName: "30E/360",
    },
    floatingDayCountFraction: {
      id: "ACT/360",
      fullName: "ACT/360",
    },
    floatingFixingDayOffset: {
      id: "-2",
      fullName: "-2",
    },
    defaultSymbolsList: [
      {
        symbol: "EUROSTR=",
        curve: "ESTR",
        itemType: "Fixing",
        tenor: "1D",
      },
      {
        symbol: "EURIBOR6MD=",
        curve: "Euribor6M",
        itemType: "Fixing",
        tenor: "6M",
      },
      {
        symbol: "EUR6MD=",
        curve: "Euribor6M",
        itemType: "Deposit",
        tenor: "6M",
      },
      {
        symbol: "EUR1X7F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "7M",
      },
      {
        symbol: "EUR2X8F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "8M",
      },
      {
        symbol: "EUR3X9F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "9M",
      },
      {
        symbol: "EUR4X10F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "10M",
      },
      {
        symbol: "EUR6X12F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "12M",
      },
      {
        symbol: "EUR9X15F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "15M",
      },
      {
        symbol: "EUR12X18F=",
        curve: "Euribor6M",
        itemType: "Forward-Rate-Agreement",
        tenor: "18M",
      },
      {
        symbol: "EURAB6E2Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "2Y",
      },
      {
        symbol: "EURAB6E3Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "3Y",
      },
      {
        symbol: "EURAB6E4Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "4Y",
      },
      {
        symbol: "EURAB6E5Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "5Y",
      },
      {
        symbol: "EURAB6E6Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "6Y",
      },
      {
        symbol: "EURAB6E7Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "7Y",
      },
      {
        symbol: "EURAB6E8Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "8Y",
      },
      {
        symbol: "EURAB6E9Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "9Y",
      },
      {
        symbol: "EURAB6E10Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "10Y",
      },
      {
        symbol: "EURAB6E11Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "11Y",
      },
      {
        symbol: "EURAB6E12Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "12Y",
      },
      {
        symbol: "EURAB6E13Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "13Y",
      },
      {
        symbol: "EURAB6E14Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "14Y",
      },
      {
        symbol: "EURAB6E15Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "15Y",
      },
      {
        symbol: "EURAB6E16Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "16Y",
      },
      {
        symbol: "EURAB6E17Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "17Y",
      },
      {
        symbol: "EURAB6E18Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "18Y",
      },
      {
        symbol: "EURAB6E19Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "19Y",
      },
      {
        symbol: "EURAB6E20Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "20Y",
      },
      {
        symbol: "EURAB6E21Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "21Y",
      },
      {
        symbol: "EURAB6E22Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "22Y",
      },
      {
        symbol: "EURAB6E23Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "23Y",
      },
      {
        symbol: "EURAB6E24Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "24Y",
      },
      {
        symbol: "EURAB6E25Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "25Y",
      },
      {
        symbol: "EURAB6E26Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "26Y",
      },
      {
        symbol: "EURAB6E27Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "27Y",
      },
      {
        symbol: "EURAB6E28Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "28Y",
      },
      {
        symbol: "EURAB6E29Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "29Y",
      },
      {
        symbol: "EURAB6E30Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "30Y",
      },
      {
        symbol: "EURAB6E40Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "40Y",
      },
      {
        symbol: "EURAB6E50Y=",
        curve: "Euribor6M",
        itemType: "Swap-Rate",
        tenor: "50Y",
      },
      {
        symbol: "EURESTSW=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "7D",
      },
      {
        symbol: "EUREST2W=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "14D",
      },
      {
        symbol: "EUREST3W=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "21D",
      },
      {
        symbol: "EUREST1M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "1M",
      },
      {
        symbol: "EUREST2M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "2M",
      },
      {
        symbol: "EUREST3M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "3M",
      },
      {
        symbol: "EUREST4M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "4M",
      },
      {
        symbol: "EUREST5M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "5M",
      },
      {
        symbol: "EUREST6M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "6M",
      },
      {
        symbol: "EUREST7M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "7M",
      },
      {
        symbol: "EUREST8M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "8M",
      },
      {
        symbol: "EUREST9M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "9M",
      },
      {
        symbol: "EUREST1Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "1Y",
      },
      {
        symbol: "EUREST15M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "15M",
      },
      {
        symbol: "EUREST18M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "18M",
      },
      {
        symbol: "EUREST21M=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "21M",
      },
      {
        symbol: "EUREST2Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "2Y",
      },
      {
        symbol: "EUREST3Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "3Y",
      },
      {
        symbol: "EUREST4Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "4Y",
      },
      {
        symbol: "EUREST5Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "5Y",
      },
      {
        symbol: "EUREST6Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "6Y",
      },
      {
        symbol: "EUREST7Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "7Y",
      },
      {
        symbol: "EUREST8Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "8Y",
      },
      {
        symbol: "EUREST9Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "9Y",
      },
      {
        symbol: "EUREST10Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "10Y",
      },
      {
        symbol: "EUREST11Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "11Y",
      },
      {
        symbol: "EUREST12Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "12Y",
      },
      {
        symbol: "EUREST15Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "15Y",
      },
      {
        symbol: "EUREST20Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "20Y",
      },
      {
        symbol: "EUREST25Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "25Y",
      },
      {
        symbol: "EUREST30Y=",
        curve: "ESTR",
        itemType: "Swap-Rate",
        tenor: "30Y",
      },
    ],
  }
];
