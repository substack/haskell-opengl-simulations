-- raytrace several ellipsoids
-- James Halliday

{-# LANGUAGE QuasiQuotes #-} -- for magical heredocs
module Main where
import Graphics.UI.GLUT.Simulation
import Control.GL.Shader (newProgram,withProgram,bindProgram,here)
import Control.Monad (forM_,liftM2)
import Data.Bits (xor)
import Foreign (newArray)
import Data.String.Utils (replace)

-- With the simulator typeclass, just create your own datatypes...
data EllipsoidSim = EllipsoidSim {
    simShader :: Program,
    checkerTex :: PixelData (Color4 GLfloat)
}

-- ...and then create instances with your type defining callbacks and such 
instance Simulation EllipsoidSim where
    display sim = runAtFPS 60 $ do
        let prog = simShader sim
        color3fM 0.8 0.8 1
        --drawFloor sim
        
        -- It turns out that the camera position can be taken right out of the
        -- projection matrix, so no need to bind any uniform variables.
        withProgram prog $ preservingMatrix $ do
            color3fM 0 1 1
            renderObject Solid $ Sphere' 10 6 6
        return sim
    
    initSimulation sim = do
        prog <- newProgram vertexShader fragmentShader
        return $ sim { simShader = prog }

vertexShader :: String
vertexShader = [$here|
    // -- vertex shader
    varying vec3 offset; // -- normalized vector offset of camera
    varying vec3 camera; // -- camera in world coords
    varying float depth;
    
    void main() {
        // -- Translation is the third column of the projection inverse.
        camera = vec3(gl_ProjectionMatrixInverse[3]);
        
        vec3 mv = vec3(gl_ModelViewMatrix * gl_Vertex);
        offset = normalize(camera - mv);
        
        gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex; 
        
        vec4 proj = gl_ProjectionMatrix * vec4(mv,1);
        depth = 0.5 + 0.5 * (proj.z / proj.w);
    }
|]
        
-- My graphics card chokes on anything but the simplest functions.
-- TODO: write a proper parser to automatically inline functions
-- since the compiler is incapable of doing this properly
ellipseF :: String
ellipseF = [$here|
    // -- Solve for the intersection of the ray with an ellipse
    // -- described by ax² + by² + cz² = -k
    {
        float a = eq.x, b = eq.y, c = eq.z, k = -eq.w;
        // P(t) = C + t * D, t >= 0
        vec3 C = camera, D = offset;
        
        // a_, b_, and c_ used to compute quadratic equation
        float a_ = (a * D.x * D.x) + (b * D.y * D.y) + (c * D.z * D.z);
        float b_ = 2.0 * (
            (a * C.x * D.x) + (b * C.y * D.y) + (c * C.z * D.z)
        );
        
        float c_ = (a * C.x * C.x)
            + (b * C.y * C.y) + (c * C.z * C.z) + k;
        if (b_ * b_ < 4 * a_ * c_) {
            t = -1.0; // non-real answer
        }
        else {
            float t1 = (-b_ + sqrt(b_*b_ - 4*a_*c_)) / (2*a_);
            float t2 = (-b_ - sqrt(b_*b_ - 4*a_*c_)) / (2*a_);
            t = min(t1,t2);
        }
    }
|]

fragmentShader :: String
fragmentShader = replace "$ellipse$" ellipseF [$here|
    // -- fragment shader
    varying vec3 camera;
    varying vec3 offset;
    varying float depth;
    
    void main() {
        gl_FragDepth = depth;
        
        vec4 eq = vec4(1.0, 1.0, 1.0, 1.0);
        vec3 pos = vec3(0.0, 0.0, 0.0);
        
        float t;
        $ellipse$ // sets t (sigh)
        
        if (t < 0.0) discard;
        
        gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
    }
|]
        
-- Draw a floor, obviously!
drawFloor :: EllipsoidSim -> IO ()
drawFloor sim = do
    tex : [] <- genObjectNames 1
    textureBinding Texture2D $= Just tex
    textureWrapMode Texture2D S $= (Repeated, ClampToEdge)
    textureWrapMode Texture2D T $= (Repeated, ClampToEdge)
    textureFilter Texture2D $= ((Nearest, Nothing), Nearest)
    
    texImage2D
        Nothing -- no cube maps
        NoProxy -- standard texture 2d
        0 -- level 0
        RGBA' -- internal format
        (TextureSize2D 19 19) -- texture size
        0 -- border
        (checkerTex sim) -- pointer to the blurred texture
    
    color4fM 1 1 1 1
    texture Texture2D $= Enabled
    renderPrimitive Quads $ do
        texCoord2fM 0 0 >> vertex3fM (-5) (-5) 0
        texCoord2fM 0 1 >> vertex3fM 5 (-5) 0
        texCoord2fM 1 1 >> vertex3fM 5 5 0
        texCoord2fM 1 0 >> vertex3fM (-5) 5 0
    texture Texture2D $= Disabled
    deleteObjectNames [tex]

main :: IO () -- what a tiny main!
main = do
    putStrLn "*** Haskell OpenGL Simulator Magic ***\n\
        \    To quit, press escape.\n\
        \    Keys:\n\
        \        forward => w, back => a,\n\
        \        left => s, right => d\n\
        \        up => q, down => z\n\
        \    Rotate: drag left mouse button\n\
        \    Skewer: drag right mouse button\n\
        \ "
    
    ptr <- newArray $ take (19 * 19)
        $ cycle [ color4f 0 0 0 0.5, color4f 1 1 1 0.5 ]
    
    runSimulation $ EllipsoidSim {
        simShader = undefined, -- filled in by initSimulation
        checkerTex = PixelData RGBA Float ptr
    }
