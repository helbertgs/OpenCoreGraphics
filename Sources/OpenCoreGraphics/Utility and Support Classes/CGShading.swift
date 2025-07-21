import Foundation
@preconcurrency import OpenGLAD

/// A class to handle OpenGL shader compilation and program management.
public class CGShading {

    var program: UInt32 = 0

    convenience init(_ type: ShaderType) {
        self.init(type.vertex, type.fragment)
    }

    init(_ vs: String, _ fs: String) {
        let vertex = compileShader(vs, type: UInt32(GL_VERTEX_SHADER))
        let fragment = compileShader(fs, type: UInt32(GL_FRAGMENT_SHADER))

        createProgram(vertex, fragment)
    }

    deinit {
        delete()
    }

    func compileShader(_ code: String, type: UInt32) -> UInt32 {
        let shader = glad_glCreateShader(type)
        code.withCString { (pointer: UnsafePointer<Int8>) in
            let shaderSource = UnsafePointer<CChar>(pointer)
            var shaderSourcePointer: UnsafePointer<GLchar>? = shaderSource
            glad_glShaderSource(shader, 1, &shaderSourcePointer, nil)
        }

        glad_glCompileShader(shader)
        debugShader(shader)
        
        return shader
    }

    func debugShader(_ shader: UInt32) {
        var success: Int32 = 0
        var infoLog = [CChar](repeating: 0, count: 1024)

        glad_glGetShaderiv(shader, UInt32(GL_COMPILE_STATUS), &success)

        if success == GL_FALSE {
            glad_glGetShaderInfoLog(shader, 1024, nil, &infoLog)
            print("Shader compilation failed:\n\(String(utf8String: infoLog) ?? "")")
        }
    }

    func debugProgram(_ program: UInt32) {
        var success: Int32 = 0
        var infoLog = [CChar](repeating: 0, count: 1024)

        glad_glGetProgramiv(program, UInt32(GL_LINK_STATUS), &success)

        if success == GL_FALSE {
            glad_glGetProgramInfoLog(program, 1024, nil, &infoLog)
            print("Program linking failed:\n\(String(utf8String: infoLog) ?? "")")
        }
    }

    func createProgram(_ vs: UInt32, _ fs: UInt32) {
        program = glad_glCreateProgram()
        
        linkProgram(vs, fs)
        debugProgram(program)
    }

    func linkProgram(_ vs: UInt32, _ fs: UInt32) {
        glad_glAttachShader(program, vs)
        glad_glAttachShader(program, fs)
        glad_glLinkProgram(program)

        deleteShader(vs)
        deleteShader(fs)
    }

    func use() {
        glad_glUseProgram(program)
    }

    func deleteShader(_ shader: UInt32) {
        glad_glDeleteShader(shader)
    }

    nonisolated func delete() {
        glad_glDeleteProgram(program)
    }

    func getUniformLocation(name: String) -> GLint {
        glad_glGetUniformLocation(program, name)
    }

     func setUniform1i(name: String, value: Int) {
        let location = getUniformLocation(name: name)
        glad_glUniform1i(location, Int32(value))
    }

    func setUniform2f(name: String, value: [Float]) {
        let location = getUniformLocation(name: name)
        glad_glUniform2f(location, value[0], value[1])
    }

    func setUniform2f(name: String, value: CGPoint) {
        let location = getUniformLocation(name: name)
        glad_glUniform2f(location, Float(value.x), Float(value.y))
    }

    func setUniform4f(name: String, value: CGColor) {
        let location = getUniformLocation(name: name)
        glad_glUniform4f(location, value.components[0], value.components[1], value.components[2], value.components[3])
    }
}

extension CGShading {
    enum ShaderType {
        case fill
        case stroke
        case image

        var vertex: String {
            return switch self {
                case .fill: """
                #version 330 core
                layout(location = 0) in vec2 aPos;

                void main() {
                    gl_Position = vec4(aPos, 0.0, 1.0);
                }
                """
                case .stroke: """
                #version 330 core
                layout(location = 0) in vec2 aPos;

                void main() {
                    gl_Position = vec4(aPos, 0.0, 1.0);
                }
                """
                case .image: """
                #version 330 core
                layout(location = 0) in vec2 aPos;
                layout(location = 1) in vec2 aTexCoord;
                out vec2 vTexCoord;
                void main() {
                    gl_Position = vec4(aPos, 0.0, 1.0);
                    vTexCoord = aTexCoord;
                }
                """
            }
        }

        var fragment: String {
            return switch self {
                case .fill: """
                #version 330 core

                out vec4 FragColor;
                uniform vec4 uColor;

                void main() {
                    FragColor = uColor;
                }
                """
                case .stroke: """
                #version 330 core

                out vec4 FragColor;
                uniform vec4 uColor;

                void main() {
                    FragColor = uColor;
                }
                """
                case .image: """
                #version 330 core
                in vec2 vTexCoord;
                out vec4 FragColor;
                uniform sampler2D uImage;
                void main() {
                    FragColor = texture(uImage, vTexCoord);
                }
                """
            }
        }
    }
}


extension CGShading {
    @MainActor public static let fillShader: CGShading = CGShading(
        """
        #version 330 core
        
        layout(location = 0) in vec2 aPos;
        out vec2 vUV;

        void main() {
            vUV = (aPos + 1.0) * 0.5; // Transform from NDC (-1,1) to UV (0,1)
            vUV.y = 1.0 - vUV.y; // Flip Y coordinate for OpenGL
            gl_Position = vec4(aPos, 0.0, 1.0);
        }
        """, 
        """
        #version 330 core

        #define MAX_POINTS 16

        in vec2 vUV;
        out vec4 FragColor;
        
        uniform vec2 uPoints[MAX_POINTS];
        uniform int uPointCount;
        uniform vec4 uColor;

        bool isPointInPolygon(vec2 point) {
            if (uPointCount < 3) return false;
            
            bool inside = false;
            for (int i = 0, j = uPointCount - 1; i < uPointCount; j = i++) {
                vec2 pi = uPoints[i];
                vec2 pj = uPoints[j];
                if ((pi.y > point.y) != (pj.y > point.y) &&
                    (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x)) {
                    inside = !inside;
                }
            }
            return inside;
        }

        void main() {
            if (isPointInPolygon(vUV)) {
                FragColor = uColor;
            } else {
                discard; // Discard pixels outside the polygon
            }
        }

        """
    )
}

extension CGShading {
    @MainActor public static let strokeShader: CGShading = CGShading(
        """
        #version 330 core
        
        layout(location = 0) in vec2 aPos;
        out vec2 vUV;

        void main() {
            vUV = (aPos + 1.0) * 0.5; // Transform from NDC (-1,1) to UV (0,1)
            vUV.y = 1.0 - vUV.y; // Flip Y coordinate for OpenGL
            gl_Position = vec4(aPos, 0.0, 1.0);
        }
        """, 
        """
        #version 330 core

        #define MAX_POINTS 16

        in vec2 vUV;
        out vec4 FragColor;
        
        uniform vec2 uPoints[MAX_POINTS];
        uniform int uPointCount;
        uniform vec4 uColor;

        bool isPointInPolygon(vec2 point) {
            if (uPointCount < 3) return false;
            
            bool inside = false;
            for (int i = 0, j = uPointCount - 1; i < uPointCount; j = i++) {
                vec2 pi = uPoints[i];
                vec2 pj = uPoints[j];
                if ((pi.y > point.y) != (pj.y > point.y) &&
                    (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x)) {
                    inside = !inside;
                }
            }
            return inside;
        }

        void main() {
            if (isPointInPolygon(vUV)) {
                FragColor = uColor;
            } else {
                discard; // Discard pixels outside the polygon
            }
        }

        """
    )
}