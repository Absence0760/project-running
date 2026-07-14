export interface LegalRepresentative {
	name: string;
	address: string;
	email: string;
}

export interface OperatorFacts {
	serviceName: string;
	controllerDescription: string;
	postalAddress: string | null;
	governingLaw: string | null;
	euRepresentative: LegalRepresentative | null;
	ukRepresentative: LegalRepresentative | null;
}

// The legal pages (/privacy, /terms, /cookie-notice) are complete legal
// text; only the operator facts below are pending. Each null renders a
// clearly-marked "pending" line on the page instead of a fabricated fact —
// the fail-closed gate per decisions §150. Filling these (plus counsel
// sign-off) is a pre-deploy checklist item, not a code change:
// docs/compliance/eu-representative.md tracks the Art 27 appointments.
export const OPERATOR: OperatorFacts = {
	serviceName: 'Threkir',
	controllerDescription: 'Jared Howard, an individual operating as a sole proprietor',
	postalAddress: null,
	governingLaw: null,
	euRepresentative: null,
	ukRepresentative: null,
};

export function operatorFactsComplete(facts: OperatorFacts): boolean {
	return (
		facts.postalAddress !== null &&
		facts.governingLaw !== null &&
		facts.euRepresentative !== null &&
		facts.ukRepresentative !== null
	);
}

export const OPERATOR_FACTS_COMPLETE = operatorFactsComplete(OPERATOR);
