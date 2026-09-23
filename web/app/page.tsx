export const viewport = { themeColor: "#f8f8f5" };

import { LandingPage, landingMetadata } from "@/features/landing";

export const metadata = landingMetadata("zh", true);

// The beta homepage renders at the domain root, including without JavaScript.
export default function Home() {
  return <LandingPage />;
}
