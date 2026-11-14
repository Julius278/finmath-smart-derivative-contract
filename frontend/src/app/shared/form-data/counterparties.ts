import { Counterparty } from "src/app/openapi/model/counterparty";

/**
 * Demo counterparties available for selection. Replace these example DLT
 * addresses when configuring actual counterparties.
 */
export const counterparties: Counterparty[] = [
  {
    bicCode: "P1BKDEMM",
    fullName: "Party One Bank",
    baseUrl: "https://www.p1bank.de/",
    dltAddress: "0x0000000000000000000000000000000000000001",
  },
  {
    bicCode: "PHCAIT3S",
    fullName: "Party Two Capital",
    baseUrl: "https://www.partytwocapital.it/",
    dltAddress: "0x0000000000000000000000000000000000000002",
  },
  {
    bicCode: "PRCKCHZH",
    fullName: "Party Three Investment",
    baseUrl: "https://zentrale.p3.ch/",
    dltAddress: "0x0000000000000000000000000000000000000003",
  },
];
