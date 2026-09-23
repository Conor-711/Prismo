export const viewport = { themeColor: "#f8f8f5" };

import { LandingPage, landingMetadata } from "@/features/landing";

export function generateMetadata({ params }: { params: { lang: string } }) {
  return landingMetadata(params.lang);
}

export default function Landing() {
  return <LandingPage />;
}
