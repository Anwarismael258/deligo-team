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
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt"><body>{children}</body></html>;
}
