{-# LANGUAGE QuasiQuotes #-} -- for heredocs
module Main where
import Graphics.UI.Simulation3D

import Foreign (newArray)
import Control.Monad.Trans (liftIO)
import Control.Applicative ((<$>))
import System.Random

data BumpReflectSim = EmptySim | BumpReflectSim {
    simShader :: Program,
    bumpTex :: PixelData (Color4 GLfloat)
}

instance Simulation BumpReflectSim where
    navigator = wasd $ WASD { rSpeed = 0.001, tSpeed = 0.05 }
    
    display = do
        prog <- simShader <$> getSimulation
        texPtr <- bumpTex <$> getSimulation
        
        mat <- cameraMatrix <$> getCamera
        let [x,y,z] = take 3 $ map (!! 3) $ toLists $ inv mat
        
        liftIO $ do
            [tex] <- genObjectNames 1
            textureBinding Texture3D $= Just tex
            textureWrapMode Texture3D S $= (Repeated, ClampToEdge)
            textureWrapMode Texture3D T $= (Repeated, ClampToEdge)
            textureFilter Texture3D $= ((Nearest, Nothing), Nearest)
            
            texImage3D
                NoProxy -- standard texture 2d
                0 -- level 0
                RGBA' -- internal format
                (TextureSize3D 30 30 30) -- texture size
                0 -- border
                texPtr -- pointer to the blurred texture
            
            color4fM 1 1 1 1
            texture Texture3D $= Enabled
            
            withProgram prog $ preservingMatrix $ do
                bindProgram prog "camera" $ vertex3f x y z
                color3fM 0 1 1
                renderObject Solid $ Sphere' 100 6 6
            
            texture Texture3D $= Disabled
            deleteObjectNames [tex]
    
    onKeyDown (Char ' ') = do
        mat <- cameraMatrix <$> getCamera
        let [x,y,z] = take 3 $ toList $ mat <> (4 |> [0,0,0,1])
        liftIO $ print (x,y,z)
    onKeyDown _ = return ()
    
    begin = do
        ptr <- liftIO $ do
            g <- newStdGen
            newArray $ take (30 ^ 3)
                $ [ color4f x x x 1.0 | x <- (randoms g :: [Float]) ]
        prog <- liftIO $ newProgram vertexShader fragmentShader
        liftIO $ bindvProgram prog "bumpTex" (30 ^ 3) ptr
        
        setWindowBG $ color4cf 0.8 0.8 1 1
        setSimulation $ BumpReflectSim {
            simShader = prog,
            bumpTex = PixelData RGBA Float ptr
        }

vertexShader :: String
vertexShader = [$here|
    // -- vertex shader
    uniform vec3 camera;
    varying vec3 ray;
    
    void main() {
        vec3 geom = vec3(gl_Vertex);
        ray = normalize(geom - camera);
        gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex; 
    }
|]

fragmentShader :: String
fragmentShader = [$here|
    // -- fragment shader
    uniform vec3 camera;
    uniform sampler3D bumpTex;
    varying vec3 ray;
    
    struct material_t {
        vec4 diffuse;
        vec4 ambient;
        float reflectivity;
    };
    
    struct intersection {
        vec3 point;
        float t;
        vec3 normal;
        int index;
        material_t material;
        vec4 color;
    };
    
    intersection sphere_intersect(vec3 E_, vec3 D, vec3 P, float r) {
        vec3 E = E_ - P;
        float a = dot(D,D);
        float b = 2.0 * dot(D,E);
        float c = dot(E,E) - r * r;
        float det = b * b - 4.0 * a * c;
        intersection ix;
        
        float a = 1.0, b = 1.0, c = 1.0, k = -1.0;
        
        // a_, b_, and c_ used to compute quadratic equation
        float a_ = (a * D.x * D.x) + (b * D.y * D.y) + (c * D.z * D.z);
        float b_ = 2.0 * (
            (a * C.x * D.x) + (b * C.y * D.y) + (c * C.z * D.z)
        );
        float c_ = (a * C.x * C.x) + (b * C.y * C.y) + (c * C.z * C.z) - k;
        
        if (b_ * b_ < 4.0 * a_ * c_) discard;
        float t1 = (-b_ + sqrt(b_ * b_ - 4.0 * a_ * c_)) / (2.0 * a_);
        float t2 = (-b_ - sqrt(b_ * b_ - 4.0 * a_ * c_)) / (2.0 * a_);
        
        float t;
        if (t1 >= 0.0 && t2 >= 0.0) {
            t = min(t1,t2); // two solutions, pick nearest
        }
        else {
            t = max(t1,t2); // one solution, pick >= 0
        }
        vec3 point = C + t * D; // point of intersection
        
        //vec3 norm = normalize(vec3(2 * point.x, 2 * point.y, 2 * point.z));
        //vec4 proj = gl_ProjectionMatrix * vec4(vec3(point),1.0);
        //gl_FragDepth = 0.1; // 0.5 + 0.5 * (proj.z / proj.w);
        //gl_FragColor = vec4(norm, 1.0);
        gl_FragColor = vec4(t1 > 0.0 ? 1.0 : 0.0, t2 > 0.0 ? 1.0 : 0.0, 0.0, 1.0);
    }
     
    intersection parabolic_intersect(vec3 E_, vec3 D, vec3 P, float A, float B) {
        // Note: this doesn't work >_<
        // hyperbolic when B < 0
        /* z = x²/a² + y²/b²
            0 = x²*b² + y²*a² - z*a²*b²
              = (E.x-t*D.x)²*b² + (E.y-t*D.y)²*a² - (E.z-t*D.z)*a²*b²
              = (E.x² - 2*t*E.x*D.x + t²*D.x²)*b²
                + (E.y² - 2*t*E.y*D.y + t²*D.y²)*a² - (E.z - t*D.z)*a²*b²
              = (b²*E.x² - 2*t*b²*E.x*D.x + t²*b²*D.x²)
                + (a²*E.y² - 2*t*a²*E.y*D.y + t²*a²*D.y²) - E.z*a²*b² + t*a²*b²*D.z
              = t²*(a²*D.y² + b²*D.x²)
                t * (-2*a²*E.y*D.y -2*b²*E.x*D.x + a²*b²*D.z)
                + b²*E.x² + a²*E.y² - E.z*a²*b²
        */
        vec3 E = E_ - P;
        float a = A*A*D.y*D.y+B*B*D.x*D.x;
        float b = -2*A*A*E.y*D.y - 2*B*B*E.x*D.x + A*A*B*B*D.z;
        float c = B*B*E.x*E.x + A*A*E.y*E.y + E.z*A*A*B*B;
        
        float det = b * b - 4.0 * a * c;
        intersection ix;
        
        if (det < 0.0) {
            ix.t = -1.0;
        }
        else {
            float t1 = (-b - sqrt(det)) / (2.0 * a);
            float t2 = (-b + sqrt(det)) / (2.0 * a);
            if (t1 > 0.0 && t2 > 0.0) ix.t = min(t1,t2);
            else ix.t = max(t1,t2);
        }
        ix.point = E + ix.t * D;
        ix.normal = normalize(ix.point);
        return ix;
    }
    
    // the meat of the geometry is in the ray casting routine
    intersection cast(vec3 E, vec3 D, int exclude = -1) {
        intersection ix_f;
        ix_f.t = -1.0;
        float sign = -1.0;
        
        for (int i = 0; i < 10; i++) {
            if (i == exclude) continue;
            intersection ix;
            ix.index = i;
            ix.material.diffuse = vec4(1.0, 1.0, 1.0, 1.0);
            ix.material.ambient = vec4(0.1, 0.1, 0.1, 1.0);
            ix.material.reflectivity = 0.0;
            
            if (i == 0) {
                ix = sphere_intersect(E, D, vec3(0.0, 0.5, 0.0), 2.0);
                ix.material.diffuse = vec4(0.9, 0.1, 0.1, 1.0);
                ix.material.reflectivity = 0.0;
            }
            else {
                // instead of a real arch, build an arch out of spheres...
                float a = -3.14159 / 8 * (i - 4 - 1);
                vec3 p = 4.0 * vec3(sin(a), 0.0, cos(a));
                ix = sphere_intersect(E, D, p, 1.0);
                ix.material.diffuse = vec4(0.1, 0.6, 0.1, 1.0);
                ix.material.reflectivity = 0.25;
            }
            
            /* if only this part worked...
            if (i == 1) {
                ix = parabolic_intersect(E, D, vec3(0.0, 0.0, 0.0), 0.5, -0.5);
                ix.material.diffuse = vec4(0.6, 1.0, 0.4, 1.0);
                ix.material.reflectivity = 0.25;
            }
            */
            
            // use the closer intersection and compute its color
            if (ix_f.t < 0.0 || (ix.t >= 0.0 && ix.t < ix_f.t)) {
                vec3 lightSource = normalize(vec3(3.0,2.0,-1.0));
                vec4 diffuse = ix.material.diffuse
                    * min(max(dot(ix.normal + D,lightSource),0.0),1.0);
                diffuse.w = ix.material.diffuse.w;
                ix.color = diffuse + ix.material.ambient;
                
                ix_f = ix;
            }
        }
        return ix_f;
    }
    
    void main() {
        // P(t) = E + t * D, t >= 0
        const vec4 sky = vec4(0.7,0.8,1.0,1.0);
        
        intersection ix = cast(camera, ray);
        if (ix.t < 0.0) ix.color = sky;
        
        vec4 proj = gl_ProjectionMatrix * vec4(ix.point,1.0);
        float depth = proj.z / proj.w;
        gl_FragDepth = clamp(0.5 + 0.5 * depth, 0.0, 1.0);
        
        intersection ix_;
        // reflect rays
        for (int i = 0; i < 3 && ix.t >= 0.0; i++) {
            if (ix.material.reflectivity > 0.0) {
                ix_ = cast(ix.point, -ix.normal, ix.index);
                if (ix_.t < 0.0) {
                    ix_.color = sky; // reflected ray hit the sky
                }
                ix_.color = ix.material.reflectivity * ix_.color
                    + (1.0 - ix.material.reflectivity) * ix.color;
                ix = ix_;
            }
        }
        
        gl_FragColor = ix.color;
    }
|]
 
main :: IO ()
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
    runSimulation EmptySim
