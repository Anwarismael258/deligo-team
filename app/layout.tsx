import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "DeliGo Triunfal HQ",
  description: "Central de Gestão e Operações",
  icons: {
    icon: "/deligo-icon.png",
    shortcut: "/deligo-icon.png",
    apple: "/deligo-icon.png",
  },
  openGraph: {
    title: "DeliGo Triunfal HQ",
    description: "Central de Gestão e Operações com dados reais das quatro plataformas.",
    images: [{ url: "/og.png", width: 1536, height: 1024, alt: "DeliGo Triunfal HQ" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "DeliGo Triunfal HQ",
    description: "Central de Gestão e Operações",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt"><body>{children}</body></html>;
}
