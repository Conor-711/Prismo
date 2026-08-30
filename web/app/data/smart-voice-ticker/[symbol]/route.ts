// Legacy API compatibility. New clients must use /data/smart-account-ticker/:symbol.
export {
  GET,
  dynamic,
  dynamicParams,
  generateStaticParams,
} from "../../smart-account-ticker/[symbol]/route";
