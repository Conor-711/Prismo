import "./index.css";
import { Composition } from "remotion";
import { Launch } from "./Composition";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Launch"
        component={Launch}
        durationInFrames={627}
        fps={30}
        width={1280}
        height={720}
      />
    </>
  );
};
